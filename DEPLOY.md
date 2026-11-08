# Deploy ContractDocumentRegistry lên Sepolia

Hướng dẫn deploy thủ công bằng PowerShell, dùng Foundry, keystore `ACCOUNT`, Alchemy và Etherscan. Các lệnh có `--broadcast` chỉ được gửi khi bạn tự chạy.

[Tổng quan contract](README.md) · [Test sau khi deploy](POST_DEPLOY_TEST.md)

## Trước khi chạy: lệnh nào gọi Solidity?

Đây là cú pháp **PowerShell trên Windows**, không phải Bash hoặc CMD. Chạy từng khối, đọc kết quả rồi mới sang khối tiếp theo. Nếu đã deploy thành công thì chuyển sang tài liệu test, không deploy lại để kiểm tra.

```text
Solidity --forge build--> ABI + bytecode trên máy
Keystore ACCOUNT --ký transaction deploy--> RPC Sepolia
EVM chạy constructor(initialOwner) --> contract mới có owner
Etherscan verify --> đối chiếu source với bytecode đã deploy
```

| Lệnh/thành phần | Làm gì? | Gọi Solidity nào? |
|---|---|---|
| `forge build` | Sinh ABI/bytecode trong out/ | Chỉ biên dịch, chưa thực thi constructor trên Sepolia |
| `forge test` | Chạy test trong EVM local | Các test gọi constructor và hàm registry, không gửi testnet |
| `cast wallet address` | Lấy địa chỉ public từ keystore | Không gọi Solidity |
| `cast chain-id`, `cast balance` | Đọc thông tin mạng/số dư ví qua RPC | Không gọi registry |
| `forge create ... --broadcast` | Ký và gửi transaction tạo contract | Chạy `constructor(address initialOwner)` |
| `forge verify-contract` | Gửi source/config compiler tới explorer để đối chiếu | Không gọi `verifyDocument()` hoặc deploy thêm contract |
| `script/DeployContractDocumentRegistry.s.sol` | Flow deploy khác qua Forge script | Hàm `run()` gọi `new ContractDocumentRegistry(initialOwner)` |

Hướng dẫn này dùng **forge create**, nên không gọi `run()` trong deploy script. `run()` cũng không phải hàm của contract registry sau deploy. Guard chain ID trong script không bảo vệ lệnh create; luôn kiểm tra RPC ở bước 2.

Trong [ContractDocumentRegistry.sol](src/ContractDocumentRegistry.sol), constructor là:

```solidity
constructor(address initialOwner) Ownable(initialOwner) {}
```

`initialOwner` nhận địa chỉ public của keystore qua `$env:REGISTRY_OWNER`. Constructor `Ownable` của OpenZeppelin đặt owner và từ chối địa chỉ zero. Constructor chỉ chạy khi tạo contract; chưa có hash PDF nào được ghi ở bước deploy.

| Giá trị | Phân biệt |
|---|---|
| `ACCOUNT=sepoliaKey` | Tên keystore mã hóa trên máy, không phải địa chỉ contract |
| `REGISTRY_OWNER` | Địa chỉ public lấy từ keystore, có quyền ghi hash |
| `$registryAddress` | Địa chỉ contract nhận được ở dòng `Deployed to` sau deploy |
| RPC/API key | Cấu hình dịch vụ, không thay thế private key để ký transaction |

Ví owner và contract là hai địa chỉ khác nhau. Mỗi lần deploy tạo contract riêng, dữ liệu proof không tự chuyển từ contract cũ sang mới.
## 1. Kiểm tra local

Mở PowerShell tại repo đã có, không chạy lại `forge init`:

```powershell
# Chọn repo chứa foundry.toml; các đường dẫn bên dưới tính từ đây.
Set-Location D:\Workspace\homespace\hs-smart-contract-blockchain
# Xem phiên bản công cụ, không kết nối blockchain.
forge --version
cast --version
# Biên dịch source thành ABI và bytecode; chưa deploy.
forge build
# Chạy unit/fuzz tests trong EVM local; không tốn Sepolia ETH.
forge test -vv
# Chỉ kiểm tra format, không tự sửa source.
forge fmt --check
```

Cấu hình giữ nguyên: Solidity `0.8.30`, EVM `cancun`, optimizer `200`. `foundry.lock` pin `forge-std v1.17.0` và `openzeppelin-contracts v5.7.0`. Chỉ khi clone mới và **thiếu** thư viện trong `lib/`, cài trước khi build:

```powershell
# Chỉ chạy khi thiếu source thư viện; không gọi Solidity hoặc deploy.
forge install foundry-rs/forge-std@v1.17.0 --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 --no-git
```

Repo giữ thư viện dưới `lib/` dạng source local được gitignore; dùng `--no-git` để không tạo submodule mới.

Nếu gặp `lib/forge-std already exists and is not a valid git repo`, kiểm tra source thay vì cài lại:

```powershell
# Chỉ kiểm tra file tồn tại trên máy, True nghĩa là có file.
Test-Path -LiteralPath lib/forge-std/src/Test.sol
Test-Path -LiteralPath lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol
```

Nếu cả hai trả `True` và `forge test --offline -vv` chạy được, bỏ qua bước install và tiếp tục. Thư mục thư viện có thể còn file `.git` trỏ tới metadata submodule không tồn tại; compiler vẫn dùng source bình thường. Không cần xóa thư viện để xử lý lỗi install này.

Tests dùng EVM local của Forge, không gửi transaction testnet. Test deploy script chỉ mô phỏng chain ID, không phải deploy Sepolia.

## 2. Keystore và cấu hình Sepolia

Chuẩn bị ví testnet riêng có Sepolia ETH trả gas, endpoint **Ethereum Sepolia** trên Alchemy và API key Etherscan. Không dùng ví có tài sản thật.

Giống crowdfunding, import ví bằng prompt tương tác vào keystore mã hóa. Nếu đã có account `sepoliaKey`, bỏ qua:

```powershell
# Chỉ import nếu alias chưa có; nhập private key/mật khẩu ở prompt.
# Không gửi transaction và không gọi hàm contract.
cast wallet import sepoliaKey --interactive
```

Nếu Cast báo `Keystore file already exists .../sepoliaKey`, account đã tồn tại: không import lại hoặc ghi đè. Dùng account hiện có để lấy địa chỉ public:

```powershell
# Lấy địa chỉ public của ví đã import; chưa gọi owner() của contract.
cast wallet address --account sepoliaKey
```

Nhập mật khẩu keystore khi được hỏi. Nếu không nhớ mật khẩu, giữ nguyên file keystore; chỉ tạo alias mới khi đã có ví testnet khác mà bạn kiểm soát.

Chỉ nhập private key tại prompt của Cast; không đặt key trong `.env`, source hoặc lệnh CLI. Không commit keystore.

```powershell
# Tạo file cấu hình nếu thiếu, giữ nguyên nếu đã có.
if (-not (Test-Path -LiteralPath .env)) { Copy-Item .env.example .env }
notepad .env
```

Điền `SEPOLIA_RPC_URL`, `ETHERSCAN_API_KEY` và `ACCOUNT=sepoliaKey`, không có dấu nháy hay comment cuối dòng. `ACCOUNT` là tên keystore đã import, không phải private key hoặc địa chỉ ví. Không cần khai báo `REGISTRY_OWNER` trong `.env`; bước dưới lấy địa chỉ public từ keystore và đặt biến này trong phiên PowerShell. `.env` đã được gitignore.

PowerShell không tự nạp `.env` vào `$env:`. Chạy nguyên khối sau; nó chỉ đọc cấu hình và kiểm tra, không gửi transaction. `ConvertFrom-StringData` đọc các dòng `KEY=value` và comment `#`, không thực thi nội dung file:

```powershell
& {
    # Xóa owner cũ để không dùng nhầm nếu lần nạp mới thất bại.
    $env:REGISTRY_OWNER = $null
    # Đọc KEY=value thành dữ liệu; không thực thi nội dung .env.
    $config = Get-Content -LiteralPath .env -Raw -ErrorAction Stop | ConvertFrom-StringData -ErrorAction Stop
    $env:SEPOLIA_RPC_URL = $config.SEPOLIA_RPC_URL
    $env:ETHERSCAN_API_KEY = $config.ETHERSCAN_API_KEY
    $env:ACCOUNT = $config.ACCOUNT

    if ([string]::IsNullOrWhiteSpace($env:SEPOLIA_RPC_URL) -or [string]::IsNullOrWhiteSpace($env:ETHERSCAN_API_KEY) -or [string]::IsNullOrWhiteSpace($env:ACCOUNT)) {
        throw 'Điền đủ SEPOLIA_RPC_URL, ETHERSCAN_API_KEY và ACCOUNT trong .env.'
    }

    # Hỏi RPC về mạng, không gọi registry. Sepolia phải là 11155111.
    $chainId = cast chain-id --rpc-url $env:SEPOLIA_RPC_URL
    if ($LASTEXITCODE -ne 0 -or "$chainId".Trim() -ne '11155111') {
        throw 'RPC phải là Ethereum Sepolia (chain ID 11155111).'
    }

    # Mở keystore ACCOUNT, lấy địa chỉ public; nhập mật khẩu khi hỏi.
    # Địa chỉ này sẽ được truyền vào constructor(address initialOwner).
    $ownerAddress = cast wallet address --account $env:ACCOUNT
    if ($LASTEXITCODE -ne 0) { throw 'Không mở được keystore đã chọn bằng ACCOUNT.' }
    $ownerAddress = "$ownerAddress".Trim()
    if ($ownerAddress -notmatch '^0x[0-9a-fA-F]{40}$' -or $ownerAddress -eq '0x0000000000000000000000000000000000000000') {
        throw 'Cast chưa trả về địa chỉ owner hợp lệ.'
    }
    $env:REGISTRY_OWNER = $ownerAddress

    # Đọc số dư ETH của ví owner, không phải số dư contract; không gửi tiền.
    cast balance $env:REGISTRY_OWNER --ether --rpc-url $env:SEPOLIA_RPC_URL
    if ($LASTEXITCODE -ne 0) { throw 'Không đọc được số dư owner.' }
}
```

Nhập mật khẩu keystore khi Cast hỏi. `REGISTRY_OWNER` được suy ra từ đúng `ACCOUNT` dùng để deploy và ghi proof; địa chỉ này là thông tin public. Nếu khối trên báo lỗi, xử lý lỗi trước khi chạy bước deploy. Nếu số dư bằng zero, nhận ETH **Sepolia** từ faucet trước khi deploy. Không gửi ETH mainnet.

## 3. Tự deploy và verify source

Lệnh sau **gửi transaction lên Sepolia khi bạn tự chạy**. Dùng `forge create` trên Windows như dự án mẫu. `--constructor-args` đặt cuối; chọn verifier Etherscan rõ ràng:

```powershell
# GỬI TRANSACTION DEPLOY: EVM chạy constructor(address initialOwner).
# Đường dẫn trước dấu : là file Solidity, phía sau là tên contract.
# --rpc-url: endpoint nhận transaction; --chain: chọn Sepolia.
# --account: keystore ký và trả gas; mật khẩu được hỏi qua prompt.
# --broadcast: thực sự gửi transaction tạo contract.
# --verify/--verifier/--etherscan-api-key: verify SOURCE trên Etherscan.
# --constructor-args: initialOwner, đặt cuối lệnh.
# Chưa gọi registerDocument() hoặc verifyDocument() ở bước này.
forge create src/ContractDocumentRegistry.sol:ContractDocumentRegistry `
    --rpc-url $env:SEPOLIA_RPC_URL `
    --chain sepolia `
    --account $env:ACCOUNT `
    --broadcast `
    --verify `
    --verifier etherscan `
    --etherscan-api-key $env:ETHERSCAN_API_KEY `
    --constructor-args $env:REGISTRY_OWNER
```

Lưu `Deployed to` và `Transaction hash`. Địa chỉ contract khác địa chỉ owner:

```powershell
# Gán địa chỉ CONTRACT từ Deployed to, không dùng địa chỉ ví owner.
$registryAddress = '0xDIA_CHI_CONTRACT_VUA_DEPLOY'
```

Tra transaction và tab Contract trên [Sepolia Etherscan](https://sepolia.etherscan.io/). Verify source đối chiếu bytecode với Solidity, khác với `verifyDocument` kiểm tra hash PDF.

Nếu deploy thành công nhưng verify source thất bại, **không deploy lại**. Dùng đúng địa chỉ contract, owner constructor và cấu hình compiler ban đầu:

```powershell
# Mã hóa constructor argument trên máy. Phải dùng owner BAN ĐẦU lúc deploy.
# Nếu đã chuyển quyền owner, không dùng owner() hiện tại thay owner ban đầu.
$constructorArgs = cast abi-encode 'constructor(address)' $env:REGISTRY_OWNER
if ($LASTEXITCODE -ne 0) { throw 'Không encode được constructor.' }
# Chỉ gửi yêu cầu verify source tới explorer; không deploy lại, không gọi verifyDocument().
# --watch chờ explorer xử lý. Giữ đúng solc/EVM/optimizer khi deploy.
forge verify-contract $registryAddress src/ContractDocumentRegistry.sol:ContractDocumentRegistry `
    --chain sepolia `
    --verifier etherscan `
    --etherscan-api-key $env:ETHERSCAN_API_KEY `
    --constructor-args $constructorArgs `
    --watch
```

Repo cũng có `script/DeployContractDocumentRegistry.s.sol`: lấy `REGISTRY_OWNER` đã suy ra từ keystore ở bước 2, signer từ CLI `--account $env:ACCOUNT`, chỉ chấp nhận chain `31337`/`11155111`. Flow trên dùng `forge create`; không chạy thêm script để tránh deploy hai lần. Guard của script không bảo vệ `forge create`, nên luôn kiểm tra RPC Sepolia ở bước 2.

## Bước tiếp theo

Lưu địa chỉ contract (`Deployed to`), transaction hash, chain ID `11155111` và địa chỉ owner ban đầu. Giữ cấu hình compiler để có thể verify source lại.

Tiếp tục [Test sau khi deploy](POST_DEPLOY_TEST.md). Không chạy lại lệnh deploy để kiểm tra contract đã có.

## Đọc kết quả và xử lý lỗi

| Kết quả | Ý nghĩa / việc tiếp theo |
|---|---|
| `Deployed to` | Địa chỉ registry mới, dùng trong tài liệu test |
| `Transaction hash` | Mã giao dịch deploy; không phải SHA-256 của PDF |
| Deploy thành công, verify lỗi | Giữ địa chỉ cũ, chạy verify lại ở bước 3; không deploy lại |
| CLI timeout sau khi gửi | Kiểm tra receipt/explorer trước khi thử deploy lại |
| Số dư ví bằng 0 | Nhận ETH Sepolia qua faucet; ETH mainnet không dùng được ở đây |
| Keystore đã tồn tại | Dùng lại ACCOUNT, không import đè |
| `cast balance` báo thiếu WHO | Chưa lấy được REGISTRY_OWNER; chạy lại khối nạp cấu hình |

Trong PowerShell, backtick ở cuối dòng nối lệnh sang dòng sau. Không thêm khoảng trắng hoặc comment sau backtick; comment được đặt ở các dòng riêng trước lệnh. Nếu terminal đang chờ `>>` do khối chưa hoàn chỉnh, nhấn Ctrl+C rồi dán lại nguyên khối.

`$LASTEXITCODE` là mã thoát CLI: 0 thành công, khác 0 là lỗi. Nó khác receipt `status`: 1 thành công, 0 là transaction revert. Nếu có lỗi trong một khối thì dừng sửa trước khi chạy khối tiếp theo.
