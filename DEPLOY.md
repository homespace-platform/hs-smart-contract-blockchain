# Deploy ContractDocumentRegistry lên Sepolia
Các khối **Output dự kiến** mô tả kết quả khi bạn tự chạy, không phải log nghiệm thu mới. Địa chỉ, hash, timestamp và số dư trong ví dụ là minh họa; không copy chúng làm input. Khối gán biến/lưu file có thể thành công mà không in gì ra console.


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

Chạy chung khối kiểm tra local: xem phiên bản, build, test và format. Chưa deploy hoặc gửi transaction.

**Output dự kiến:** in phiên bản Forge/Cast, thông báo compile và kết quả test pass/fail. `forge fmt --check` thường không in gì khi đạt. Chỉ tiếp tục nếu build/test/format đều thành công; số test và phiên bản phụ thuộc source/công cụ hiện tại.

```powershell
# Chạy khối này sau khi đọc hướng dẫn phía trên
Set-Location D:\Workspace\homespace\hs-smart-contract-blockchain
forge --version
cast --version
forge build
forge test -vv
forge fmt --check
```

Cấu hình giữ nguyên: Solidity `0.8.30`, EVM `cancun`, optimizer `200`. `foundry.lock` pin `forge-std v1.17.0` và `openzeppelin-contracts v5.7.0`. Chỉ khi clone mới và **thiếu** thư viện trong `lib/`, cài trước khi build:

Chỉ chạy chung hai lệnh cài dependency nếu thiếu thư viện; tên repository và tag xác định phiên bản, --no-git không tạo submodule.

**Output dự kiến:** thông báo tải/cài từng thư viện, tùy phiên bản Forge. Thành công khi lệnh kết thúc không lỗi và source dependency xuất hiện trong `lib/`. Không sinh địa chỉ contract.

```powershell
# Chạy khối này sau khi đọc hướng dẫn phía trên
forge install foundry-rs/forge-std@v1.17.0 --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 --no-git
```

Repo giữ thư viện dưới `lib/` dạng source local được gitignore; dùng `--no-git` để không tạo submodule mới.

Nếu gặp `lib/forge-std already exists and is not a valid git repo`, kiểm tra source thay vì cài lại:

Chạy chung hai lệnh kiểm tra file; mỗi True nghĩa là source dependency tương ứng đã có.

**Output dự kiến:** hai dòng ứng với hai file, theo đúng thứ tự lệnh:

```text
True
True
```

```powershell
# Chạy khối này sau khi đọc hướng dẫn phía trên
Test-Path -LiteralPath lib/forge-std/src/Test.sol
Test-Path -LiteralPath lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol
```

Nếu cả hai trả `True` và `forge test --offline -vv` chạy được, bỏ qua bước install và tiếp tục. Thư mục thư viện có thể còn file `.git` trỏ tới metadata submodule không tồn tại; compiler vẫn dùng source bình thường. Không cần xóa thư viện để xử lý lỗi install này.

Tests dùng EVM local của Forge, không gửi transaction testnet. Test deploy script chỉ mô phỏng chain ID, không phải deploy Sepolia.

## 2. Keystore và cấu hình Sepolia

Chuẩn bị ví testnet riêng có Sepolia ETH trả gas, endpoint **Ethereum Sepolia** trên Alchemy và API key Etherscan. Không dùng ví có tài sản thật.

Giống crowdfunding, import ví bằng prompt tương tác vào keystore mã hóa. Nếu đã có account `sepoliaKey`, bỏ qua:

Chạy riêng khi alias chưa có. wallet import nhận tên sepoliaKey; --interactive yêu cầu nhập private key và mật khẩu qua prompt. Không gọi Solidity.

**Output dự kiến:** prompt yêu cầu private key rồi mật khẩu bảo vệ keystore; sau đó thông báo import thành công. Không có transaction hash hay địa chỉ contract. Nếu alias đã tồn tại, bỏ qua import và dùng keystore cũ.

```powershell
# Chạy khối này sau khi đọc hướng dẫn phía trên
cast wallet import sepoliaKey --interactive
```

Nếu Cast báo `Keystore file already exists .../sepoliaKey`, account đã tồn tại: không import lại hoặc ghi đè. Dùng account hiện có để lấy địa chỉ public:

Chạy riêng để lấy địa chỉ public từ alias sepoliaKey. Đây là thao tác keystore trên máy, không gọi owner() của registry.

**Output dự kiến:** prompt mật khẩu và một địa chỉ public của ví (địa chỉ dưới đây chỉ minh họa):

```text
Enter keystore password:
0x1111111111111111111111111111111111111111
```

```powershell
# Chạy khối này sau khi đọc hướng dẫn phía trên
cast wallet address --account sepoliaKey
```

Nhập mật khẩu keystore khi được hỏi. Nếu không nhớ mật khẩu, giữ nguyên file keystore; chỉ tạo alias mới khi đã có ví testnet khác mà bạn kiểm soát.

Chỉ nhập private key tại prompt của Cast; không đặt key trong `.env`, source hoặc lệnh CLI. Không commit keystore.

Chạy chung để tạo .env nếu thiếu và mở editor. Lưu file, đóng editor rồi mới sang bước nạp cấu hình.

**Output dự kiến:** editor mở `.env`; console không cần in giá trị nào. Bạn lưu file với đủ ba biến rồi đóng editor trước khi tiếp tục.

```powershell
# Chạy khối này sau khi đọc hướng dẫn phía trên
if (-not (Test-Path -LiteralPath .env)) { Copy-Item .env.example .env }
notepad .env
```

Điền `SEPOLIA_RPC_URL`, `ETHERSCAN_API_KEY` và `ACCOUNT=sepoliaKey`, không có dấu nháy hay comment cuối dòng. `ACCOUNT` là tên keystore đã import, không phải private key hoặc địa chỉ ví. Không cần khai báo `REGISTRY_OWNER` trong `.env`; bước dưới lấy địa chỉ public từ keystore và đặt biến này trong phiên PowerShell. `.env` đã được gitignore.

PowerShell không tự nạp `.env` vào `$env:`. Chạy nguyên khối sau; nó chỉ đọc cấu hình và kiểm tra, không gửi transaction. `ConvertFrom-StringData` đọc các dòng `KEY=value` và comment `#`, không thực thi nội dung file:

Chạy nguyên khối nạp cấu hình và kiểm tra mạng/số dư. ACCOUNT chọn keystore; địa chỉ lấy được đặt vào REGISTRY_OWNER để truyền cho constructor. Chưa gọi registry hoặc gửi transaction.

**Output dự kiến:** prompt mật khẩu keystore và số dư ví theo ETH, ví dụ dưới đây là 0.05 Sepolia ETH. Chain ID/địa chỉ owner được gán vào biến nên không tự in ra. Nếu lỗi kiểm tra, khối ném thông báo và dừng:

```text
Enter keystore password:
0.05
```

```powershell
# Chạy khối này sau khi đọc hướng dẫn phía trên
& {
    $env:REGISTRY_OWNER = $null
    $config = Get-Content -LiteralPath .env -Raw -ErrorAction Stop | ConvertFrom-StringData -ErrorAction Stop
    $env:SEPOLIA_RPC_URL = $config.SEPOLIA_RPC_URL
    $env:ETHERSCAN_API_KEY = $config.ETHERSCAN_API_KEY
    $env:ACCOUNT = $config.ACCOUNT

    if ([string]::IsNullOrWhiteSpace($env:SEPOLIA_RPC_URL) -or [string]::IsNullOrWhiteSpace($env:ETHERSCAN_API_KEY) -or [string]::IsNullOrWhiteSpace($env:ACCOUNT)) {
        throw 'Điền đủ SEPOLIA_RPC_URL, ETHERSCAN_API_KEY và ACCOUNT trong .env.'
    }

    $chainId = cast chain-id --rpc-url $env:SEPOLIA_RPC_URL
    if ($LASTEXITCODE -ne 0 -or "$chainId".Trim() -ne '11155111') {
        throw 'RPC phải là Ethereum Sepolia (chain ID 11155111).'
    }

    $ownerAddress = cast wallet address --account $env:ACCOUNT
    if ($LASTEXITCODE -ne 0) { throw 'Không mở được keystore đã chọn bằng ACCOUNT.' }
    $ownerAddress = "$ownerAddress".Trim()
    if ($ownerAddress -notmatch '^0x[0-9a-fA-F]{40}$' -or $ownerAddress -eq '0x0000000000000000000000000000000000000000') {
        throw 'Cast chưa trả về địa chỉ owner hợp lệ.'
    }
    $env:REGISTRY_OWNER = $ownerAddress

    cast balance $env:REGISTRY_OWNER --ether --rpc-url $env:SEPOLIA_RPC_URL
    if ($LASTEXITCODE -ne 0) { throw 'Không đọc được số dư owner.' }
}
```

Nhập mật khẩu keystore khi Cast hỏi. `REGISTRY_OWNER` được suy ra từ đúng `ACCOUNT` dùng để deploy và ghi proof; địa chỉ này là thông tin public. Nếu khối trên báo lỗi, xử lý lỗi trước khi chạy bước deploy. Nếu số dư bằng zero, nhận ETH **Sepolia** từ faucet trước khi deploy. Không gửi ETH mainnet.

## 3. Tự deploy và verify source

Lệnh sau **gửi transaction lên Sepolia khi bạn tự chạy**. Dùng `forge create` trên Windows như dự án mẫu. `--constructor-args` đặt cuối; chọn verifier Etherscan rõ ràng:

Chạy riêng sau khi kiểm tra cấu hình. create gọi constructor(address initialOwner) với initialOwner = REGISTRY_OWNER. --account chọn ví ký/trả gas; --rpc-url/--chain chọn Sepolia; --broadcast gửi transaction; --verify/--verifier/--etherscan-api-key phục vụ verify source. --constructor-args đặt cuối lệnh.

**Output dự kiến:** địa chỉ ví gửi, địa chỉ contract mới và transaction hash. Các giá trị sau chỉ minh họa; thông báo verify source có thể khác giữa các phiên bản Forge:

```text
Deployer: 0x1111111111111111111111111111111111111111
Deployed to: 0x2222222222222222222222222222222222222222
Transaction hash: 0x3333333333333333333333333333333333333333333333333333333333333333
```

**Cách đọc:** `Deployed to` là `$registryAddress`; `Transaction hash` dùng tra explorer. Constructor không trả về dữ liệu nghiệp vụ hoặc hash PDF. Nếu deploy đã thành công nhưng verification lỗi, giữ địa chỉ này và chỉ verify source lại.

```powershell
# Chạy khối này sau khi đọc hướng dẫn phía trên
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

Thay placeholder bằng Deployed to rồi chạy riêng dòng gán địa chỉ contract, dùng cho phần test.

**Output dự kiến:** không in gì; chỉ đặt `$registryAddress` trong phiên PowerShell. Không tạo contract hay gửi transaction.

```powershell
# Chạy khối này sau khi đọc hướng dẫn phía trên
$registryAddress = '0xDIA_CHI_CONTRACT_VUA_DEPLOY'
```

Tra transaction và tab Contract trên [Sepolia Etherscan](https://sepolia.etherscan.io/). Verify source đối chiếu bytecode với Solidity, khác với `verifyDocument` kiểm tra hash PDF.

Nếu deploy thành công nhưng verify source thất bại, **không deploy lại**. Dùng đúng địa chỉ contract, owner constructor và cấu hình compiler ban đầu:

Chỉ chạy chung khối dưới khi deploy đã thành công nhưng verify source thất bại. abi-encode mã hóa initialOwner BAN ĐẦU; verify-contract nhận địa chỉ contract, source và constructor argument, --watch chờ explorer xử lý. Không gọi verifyDocument() hoặc deploy lại.

**Output dự kiến:** thông báo tiến trình/kết quả verify source từ Etherscan. Chuỗi constructor được lưu vào `$constructorArgs`, không tự in. Thành công khi explorer báo source đã verified; không xuất hiện địa chỉ deploy mới. Nếu thất bại, đọc nguyên nhân từ verifier, không chạy deploy lại.

```powershell
# Chạy khối này sau khi đọc hướng dẫn phía trên
$constructorArgs = cast abi-encode 'constructor(address)' $env:REGISTRY_OWNER
if ($LASTEXITCODE -ne 0) { throw 'Không encode được constructor.' }
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
