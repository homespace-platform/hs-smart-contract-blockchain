# ContractDocumentRegistry — triển khai và kiểm tra trên Sepolia
Các khối **Output dự kiến** mô tả kết quả khi bạn tự chạy, không phải log nghiệm thu mới. Địa chỉ, hash, timestamp và số dư trong ví dụ là minh họa; không copy chúng làm input. Khối gán biến/lưu file có thể thành công mà không in gì ra console.


Hướng dẫn deploy thủ công bằng PowerShell, dùng Foundry, keystore `ACCOUNT`, Alchemy và Etherscan. Các lệnh có `--broadcast` chỉ được gửi khi bạn tự chạy.

[Tổng quan contract](README.md)

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

Tiếp tục phần kiểm tra sau khi deploy bên dưới. Không chạy lại lệnh deploy để kiểm tra contract đã có.

Sau khi test thành công, cập nhật **`CONTRACT_DOCUMENT_REGISTRY_ADDRESS` của backend** bằng địa chỉ `Deployed to` vừa nhận và khởi động lại backend. ABI ghi proof của backend dùng `registerDocumentWithLineage`; địa chỉ registry cũ sẽ không tương thích. Các proof cũ trên registry cũ vẫn tra được ở địa chỉ cũ nếu bạn còn lưu lại; chúng không tự chuyển sang registry mới.

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

---

## Kiểm tra sau khi deploy ContractDocumentRegistry
Các khối **Output dự kiến** mô tả kết quả khi bạn tự chạy, không phải log nghiệm thu mới. Địa chỉ, hash, timestamp và số dư trong ví dụ là minh họa; không copy chúng làm input. Khối gán biến/lưu file có thể thành công mà không in gì ra console.


Dùng địa chỉ contract đã deploy ở phần trên. Tài liệu này không tạo contract mới. Phần ghi proof gửi transaction và tốn Sepolia ETH; phần đọc/đối chiếu không tốn gas.

### Bản đồ CLI → Solidity

Cú pháp bên dưới là **PowerShell**, không phải Bash/CMD. Chạy từng khối và đọc kết quả. Xem [source registry](src/ContractDocumentRegistry.sol) song song với tài liệu này.

| Lệnh | Phần source được thực thi | Ghi blockchain / trả gas? |
|---|---|---|
| `cast code` | Đọc runtime bytecode, không gọi hàm Solidity | Không |
| `cast call ... owner()` | `owner()` kế thừa từ OpenZeppelin Ownable | Không |
| `cast send ... registerDocumentWithLineage(...)` | Ghi hash, mã hồ sơ và loại văn bản; chạy `onlyOwner` trước | Có |
| `cast call ... documents(...)` | Getter compiler tự sinh cho mapping public documents | Không |
| `cast call ... verifyDocument(...)` | Hàm view verifyDocument trong registry | Không |
| `Get-FileHash -Algorithm SHA256` | Hash bytes PDF trên máy, không gọi Solidity | Không |
| `cast keccak` | Hash chuỗi GUID trên máy để tạo ID, không gọi registry | Không |

`cast call` dùng RPC eth_call để node thực thi và trả kết quả, không lưu thay đổi vào chain. `cast send` ký và gửi transaction thật. Cả hai dùng ABI để mã hóa lời gọi.

```text
verifyDocument(bytes32,bytes32)(bool)
  tên hàm     kiểu 2 tham số   kiểu trả về để Cast giải mã
owner()(address)
 tên hàm, không có tham số, trả về address
```

`bytes32` là 32 byte (0x + 64 ký tự hex); address là 20 byte (0x + 40 ký tự hex). Các dấu nháy giữ chữ ký hàm thành một tham số chuỗi cho Cast.

| Giá trị | Ý nghĩa |
|---|---|
| documentId | Key riêng của một tài liệu/phiên bản; tạo một lần, giữ khi retry/verify |
| documentHash | SHA-256 của đúng bytes PDF; không phải hash URL hoặc JSON |
| registryAddress | Địa chỉ contract, không phải ví owner |
| transactionHash | Mã transaction sau khi gửi; không phải documentHash |
### 1. Chuẩn bị phiên PowerShell

Nếu mở terminal mới, nạp lại RPC và tên keystore từ `.env`. Không cần Etherscan API key cho các bài test này. Thay địa chỉ mẫu bằng giá trị `Deployed to`, không dùng địa chỉ ví:

Chạy chung phần nạp cấu hình và kiểm tra Sepolia. Gán địa chỉ contract ở khối riêng tiếp theo.

**Output dự kiến:** không in gì khi cấu hình hợp lệ vì chain ID được gán vào biến. Nếu thiếu biến hoặc RPC không thuộc Sepolia, khối ném thông báo lỗi và bạn dừng tại đây.

```powershell
# Nạp cấu hình và kiểm tra mạng
Set-Location D:\Workspace\homespace\hs-smart-contract-blockchain

& {
    $config = Get-Content -LiteralPath .env -Raw -ErrorAction Stop | ConvertFrom-StringData -ErrorAction Stop
    $env:SEPOLIA_RPC_URL = $config.SEPOLIA_RPC_URL
    $env:ACCOUNT = $config.ACCOUNT
    if ([string]::IsNullOrWhiteSpace($env:SEPOLIA_RPC_URL) -or [string]::IsNullOrWhiteSpace($env:ACCOUNT)) {
        throw 'Điền SEPOLIA_RPC_URL và ACCOUNT trong .env.'
    }
    $chainId = cast chain-id --rpc-url $env:SEPOLIA_RPC_URL
    if ($LASTEXITCODE -ne 0 -or "$chainId".Trim() -ne '11155111') {
        throw 'RPC phải là Ethereum Sepolia (chain ID 11155111).'
    }
}
```

Thay placeholder bằng Deployed to rồi chạy riêng dòng gán sau:

**Output dự kiến:** không in gì; `$registryAddress` nhận địa chỉ contract đã có.

```powershell
# Chọn contract đã deploy
$registryAddress = '0xDIA_CHI_CONTRACT_DA_DEPLOY'
```

Nếu có lỗi ở bước chuẩn bị, xử lý xong trước khi chạy tiếp.

### 2. Kiểm tra contract và owner

Các lệnh đọc không tốn gas:

Chạy chung hai lệnh chỉ đọc: code nhận địa chỉ registry để đọc bytecode; call gọi owner() không có tham số và trả address. Kỳ vọng có bytecode và owner khớp ví có quyền ghi.

**Output dự kiến:** dòng bytecode dài rồi địa chỉ owner; giá trị dưới đây chỉ minh họa:

```text
0x60806040...
0x1111111111111111111111111111111111111111
```

**Cách đọc:** kết quả lệnh đầu chỉ `0x` nghĩa là không có code tại địa chỉ trên mạng này. Dòng địa chỉ của lệnh thứ hai là ví có quyền ghi, không phải địa chỉ contract.

```powershell
# Chạy khối này theo hướng dẫn phía trên
cast code $registryAddress --rpc-url $env:SEPOLIA_RPC_URL
cast call $registryAddress 'owner()(address)' --rpc-url $env:SEPOLIA_RPC_URL
```

- `cast code`: đọc bytecode tại địa chỉ contract; chuỗi dài `0x6080...` là có code, chỉ `0x` là không có code trên mạng đang kiểm tra.
- `cast call ... owner()`: đọc địa chỉ ví hiện có quyền ghi hash. Kết quả phải khớp ví owner đã cấu hình khi deploy, hoặc owner mới nếu bạn đã chuyển quyền.
- Cả hai lệnh trên chỉ đọc dữ liệu, không gửi transaction. Có bytecode chưa đủ để xác nhận đó là đúng contract; đối chiếu thêm địa chỉ và source đã verify trên Etherscan.

### 3. Ghi hash PDF và kiểm tra khớp

Chọn PDF thử nghiệm trên máy, tạo documentId **một lần** và lưu lại trước khi gửi. Giữ ID này khi kiểm tra/retry:

#### 3.1. Chọn PDF

Thay đường dẫn và chạy riêng dòng gán. Chưa tính hash hoặc gọi Solidity.

**Output dự kiến:** không in gì; `$pdfPath` chỉ lưu đường dẫn. File chưa được đọc, chưa có ID/hash mới.

```powershell
# Chọn PDF
$pdfPath = 'D:\duong-dan\hop-dong-da-ky.pdf'
```

#### 3.2. Chuẩn bị và lưu dữ liệu

Chạy chung khối dưới một lần cho proof mới: keccak(GUID) tạo ID bytes32; Get-FileHash tính SHA-256 của PDF; JSON lưu metadata public để giữ ID/hash khi retry. Khối này chưa gọi Solidity. File JSON nằm trong thư mục repo, không chứa PDF, API key hoặc mật khẩu.

**Output dự kiến:** console không in ID/hash vì chúng được gán vào biến. Khối tạo file `proof-<documentId>.json` trong thư mục repo, chứa `chainId`, `registryAddress`, `documentId`, `documentHash`. `chainId` phải là 11155111; hai giá trị ID/hash có dạng `0x` + 64 ký tự hex. Nếu file không tồn tại hoặc không đọc được, `Get-FileHash` báo lỗi; chưa gửi transaction.

```powershell
# Tạo ID, hash và lưu metadata trên máy
$documentId = cast keccak ([guid]::NewGuid().ToString())
if ($LASTEXITCODE -ne 0) { throw 'Không tạo được documentId.' }
$caseId = cast keccak ([guid]::NewGuid().ToString())
if ($LASTEXITCODE -ne 0) { throw 'Không tạo được caseId.' }
$documentKind = 1 # HĐ cọc; dùng 2 cho HĐ thuê, 3 cho phụ lục của cùng caseId.
$documentHash = '0x' + (Get-FileHash -LiteralPath $pdfPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()

$proofFile = Join-Path (Get-Location) ("proof-{0}.json" -f $documentId)
[ordered]@{
    chainId = 11155111
    registryAddress = $registryAddress
    documentId = $documentId
    documentHash = $documentHash
    caseId = $caseId
    documentKind = $documentKind
} | ConvertTo-Json | Set-Content -LiteralPath $proofFile -Encoding UTF8
```

#### 3.3. Gửi proof lên blockchain

Dừng để kiểm tra đúng file, ID, hash và contract address trước khi chạy riêng khối tiếp theo.

Gọi `registerDocumentWithLineage(documentId, documentHash, caseId, documentKind)`: truyền ID file, SHA-256, mã hồ sơ, loại văn bản theo đúng thứ tự. Cùng hồ sơ dùng lại `$caseId` nhưng mỗi PDF ký đủ dùng `$documentId` mới. Chỉ owner được ghi; ID/hash/caseId phải khác zero, kind là 1–3. `--account` chọn keystore ký/trả gas; không truyền `--value`.

**Output dự kiến:** prompt mật khẩu và transaction receipt, không phải giá trị trả về của hàm Solidity (hàm không khai báo `returns`). Receipt minh họa, các trường khác được lược bớt:

```text
Enter keystore password:
blockNumber          12000000
from                 0x1111111111111111111111111111111111111111
to                   0x2222222222222222222222222222222222222222
status               1 (success)
transactionHash      0x3333333333333333333333333333333333333333333333333333333333333333
logs                 [...]
```

**Cách đọc:** `status 1` là transaction thực thi thành công. `logs` phải có event `DocumentRegistered` đúng ID/hash. `status 0` hoặc lỗi revert là thất bại; timeout cần kiểm tra proof/receipt trước khi retry.

| Trường trong receipt | Hiểu đơn giản |
|---|---|
| `transactionHash` | Mã giao dịch để lưu lại và tra trên Etherscan. |
| `from` / `to` | Ví ký và trả phí / địa chỉ registry được gọi (`$registryAddress`). |
| `blockNumber` / `blockHash` | Số thứ tự / mã định danh block chứa giao dịch. |
| `gasUsed` / `effectiveGasPrice` | Lượng gas đã dùng / giá mỗi đơn vị gas tính bằng wei. Nhân hai số ra phí giao dịch. |
| `cumulativeGasUsed` | Tổng gas từ đầu block đến hết giao dịch này; không phải gas riêng bạn trả. |
| `transactionIndex` | Vị trí giao dịch trong block, đếm từ 0. Ví dụ `50` là giao dịch thứ 51. |
| `contractAddress` trống | Bình thường khi gọi contract có sẵn; trường này dùng khi tạo contract mới. |
| `logs` | Sự kiện `DocumentRegistered`, chứa ID, hash, ví ghi nhận và thời điểm; không chứa PDF. |
| `type: 2` | Giao dịch sử dụng cơ chế phí EIP-1559. |
| `logsBloom` | Bộ lọc hỗ trợ tìm sự kiện; có thể bỏ qua khi kiểm tra thủ công. |
| `root`, `blobGasPrice`, `blobGasUsed` trống | Các trường không áp dụng cho receipt/giao dịch này. |

Ví dụ receipt của bạn: `241180 × 50000019 wei = 0.00001205900458242 ETH` phí gas. Trên Etherscan, **Value: 0 ETH** nghĩa là không chuyển ETH vào contract; ví vẫn trả phí gas bằng Sepolia ETH. **Block Confirmations** là số xác nhận Etherscan ghi nhận; **Timestamp** là thời gian block chứa giao dịch.

Trong `logs`: `topics[0]` nhận diện loại sự kiện; `topics[1]`, `[2]`, `[3]` lần lượt là `documentId`, `documentHash`, `recorder` (ví được đệm đủ 32 byte); `data` chứa `registeredAt`. `logIndex` là vị trí sự kiện trong block, đếm từ 0; `removed: false` nghĩa là log chưa bị đánh dấu loại bỏ do tổ chức lại chuỗi. Thời điểm này không phải ngày ký PDF.

```powershell
# Gửi transaction có mã hồ sơ thủ công
cast send $registryAddress 'registerDocumentWithLineage(bytes32,bytes32,bytes32,uint8)' $documentId $documentHash $caseId $documentKind `
    --rpc-url $env:SEPOLIA_RPC_URL `
    --chain sepolia `
    --account $env:ACCOUNT
if ($LASTEXITCODE -ne 0) { throw 'Gửi proof thất bại; đọc proof trước khi retry.' }
```

#### 3.4. Đọc proof sau khi gửi thành công

Chỉ chạy khối đọc sau khi receipt có status 1. Getter documents(documentId) trả (documentHash, registeredAt); verifyDocument(documentId, documentHash) trả bool, kỳ vọng true. Hai lệnh có thể chạy chung và không tốn gas.

**Output dự kiến:** hash đã lưu, timestamp giây, kết quả verify, mã hồ sơ, loại văn bản, ID HĐ cọc và ID HĐ thuê; dữ liệu dưới đây minh họa cho `$documentKind = 1`:

```text
0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
1794121512 [1.794e9]
true
0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
1
0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
0x0000000000000000000000000000000000000000000000000000000000000000
```

**Cách đọc:** hash dòng đầu phải khớp `$documentHash`; dòng thứ hai là thời điểm block; dòng `true` xác nhận ID/hash khớp; dòng 4–5 phải khớp `$caseId` và `$documentKind`. Với kind 1, dòng 6 là `$documentId`, dòng 7 là zero vì chưa có HĐ thuê. Với kind 2, dòng 7 là `$documentId`; với kind 3, dòng 7 vẫn là ID HĐ thuê. Getter của ID chưa tồn tại trả zero.

```powershell
# Đọc proof và đối chiếu hash đã gửi
cast call $registryAddress 'documents(bytes32)(bytes32,uint256)' $documentId `
    --rpc-url $env:SEPOLIA_RPC_URL
cast call $registryAddress 'verifyDocument(bytes32,bytes32)(bool)' $documentId $documentHash `
    --rpc-url $env:SEPOLIA_RPC_URL
cast call $registryAddress 'caseIds(bytes32)(bytes32)' $documentId --rpc-url $env:SEPOLIA_RPC_URL
cast call $registryAddress 'documentKinds(bytes32)(uint8)' $documentId --rpc-url $env:SEPOLIA_RPC_URL
cast call $registryAddress 'caseDeposits(bytes32)(bytes32)' $caseId --rpc-url $env:SEPOLIA_RPC_URL
cast call $registryAddress 'caseLeases(bytes32)(bytes32)' $caseId --rpc-url $env:SEPOLIA_RPC_URL
```

Kết quả phải là `true`.


#### Solidity xử lý lời gọi ghi proof như thế nào?

```solidity
function registerDocumentWithLineage(bytes32 documentId, bytes32 documentHash,
    bytes32 caseId, uint8 kind) external onlyOwner {
    if (caseId == bytes32(0) || kind < 1 || kind > 3
        || kind == 1 && caseDeposits[caseId] != bytes32(0)
        || kind == 2 && caseLeases[caseId] != bytes32(0)
        || kind == 3 && caseLeases[caseId] == bytes32(0)) revert InvalidLineage(caseId, kind);
    _register(documentId, documentHash);
    documentKinds[documentId] = kind;
    caseIds[documentId] = caseId;
    if (kind == 1) caseDeposits[caseId] = documentId;
    if (kind == 2) caseLeases[caseId] = documentId;
    emit DocumentLineageRegistered(caseId, documentId, kind);
}

function _register(bytes32 documentId, bytes32 documentHash) private {
    if (documentId == bytes32(0)) revert InvalidDocumentId();
    if (documentHash == bytes32(0)) revert InvalidDocumentHash();
    if (documents[documentId].documentHash != bytes32(0)) revert DocumentAlreadyRegistered(documentId);

    documents[documentId] = DocumentProof(documentHash, block.timestamp);
    emit DocumentRegistered(documentId, documentHash, msg.sender, block.timestamp);
}
```

Thứ tự: `onlyOwner` kiểm tra ví → kiểm tra mã hồ sơ/loại văn bản → `_register` từ chối ID/hash zero hoặc trùng, ghi hash và phát event → lưu mã hồ sơ/loại văn bản. Nếu bất kỳ bước nào revert, toàn bộ transaction rollback. Contract không đọc PDF hoặc kiểm tra chữ ký SmartCA; owner cung cấp hash đầu vào.

Getter `documents()` không có khai báo function riêng vì compiler tự sinh từ dòng:

```solidity
mapping(bytes32 documentId => DocumentProof proof) public documents;
```

Còn lời gọi verify chạy đúng hàm này:

```solidity
function verifyDocument(bytes32 documentId, bytes32 documentHash) external view returns (bool) {
    bytes32 storedHash = documents[documentId].documentHash;
    return storedHash != bytes32(0) && storedHash == documentHash;
}
```

`view` không cập nhật dữ liệu. Kiểm tra storedHash khác zero khiến ID chưa tồn tại và hash zero vẫn trả false. Hash khớp chỉ đối chiếu commitment, không chứng minh danh tính người ký hay nội dung nghiệp vụ đúng.

Nếu CLI timeout sau khi gửi, đọc lại documents(id) trước khi retry. Cùng ID/hash đã có thì tiếp tục verify; khác hash thì dừng đối chiếu. Gửi lại cùng ID sẽ revert kể cả hash giống nhau.
### 4. Kiểm tra file khác và ID chưa tồn tại

Tính SHA-256 của một PDF khác/đã sửa rồi gọi `verifyDocument` với **cùng documentId**: kết quả phải là `false`. ID chưa tồn tại và hash zero cũng phải trả `false`:

Chạy chung khối test ID chưa tồn tại: tạo unknownId chưa đăng ký, truyền unknownId và bytes32 zero cho verifyDocument(id, hash). Kỳ vọng false, không ghi proof.

**Output dự kiến:** một giá trị bool:

```text
false
```

Điều này đúng ngay cả khi cả stored hash mặc định và hash truyền vào đều zero, vì `verifyDocument` yêu cầu proof đã tồn tại.

```powershell
# Chạy khối này theo hướng dẫn phía trên
$unknownId = cast keccak ([guid]::NewGuid().ToString())
$zeroHash = '0x' + ('0' * 64)
cast call $registryAddress 'verifyDocument(bytes32,bytes32)(bool)' $unknownId $zeroHash `
    --rpc-url $env:SEPOLIA_RPC_URL
```


#### 4.1. Kiểm tra lại PDF hiện tại thay vì chỉ dùng biến hash cũ

Chạy chung để tính lại SHA-256 của PDF hiện tại rồi gọi verifyDocument(documentId, currentHash). Giữ nguyên ID đã đăng ký; kết quả bool phải là true nếu bytes file không đổi.

**Output dự kiến:** một giá trị bool:

```text
true
```

Nếu trả `false`, bytes file hiện tại khác hash đã ghi hoặc bạn đang dùng sai ID/contract/network. Lỗi RPC/ABI là lỗi lệnh, không phải kết quả bool `false`.

```powershell
# Chạy khối này theo hướng dẫn phía trên
$currentHash = '0x' + (Get-FileHash -LiteralPath $pdfPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()

cast call $registryAddress 'verifyDocument(bytes32,bytes32)(bool)' $documentId $currentHash --rpc-url $env:SEPOLIA_RPC_URL
```

Nếu chỉ truyền biến documentHash cũ, bạn chưa thực sự kiểm tra bytes của PDF hiện tại.

#### 4.2. Kiểm tra PDF khác bytes, giữ cùng ID

Chuẩn bị một PDF khác hoặc sửa một bản sao, giữ nguyên file gốc. Chỉ đổi tên file nhưng nội dung bytes không đổi thì hash vẫn giống và true là đúng.

Thay đường dẫn PDF khác nội dung rồi chạy chung khối tính hash và đối chiếu. verifyDocument nhận ID cũ và otherHash; kỳ vọng false.

**Output dự kiến:** một giá trị bool:

```text
false
```

Đây là kết quả mong đợi khi ID giữ nguyên nhưng hash khác. Nếu hai file có cùng hash, lệnh kiểm tra báo lỗi; dừng và chọn file khác nội dung trước khi tiếp tục gọi verify.

```powershell
# Chạy khối này theo hướng dẫn phía trên
$otherPdfPath = 'D:\duong-dan\hop-dong-ban-sua.pdf'
$otherHash = '0x' + (Get-FileHash -LiteralPath $otherPdfPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
if ($otherHash -eq $documentHash) { throw 'Hai file cùng hash; chọn file khác nội dung.' }

cast call $registryAddress 'verifyDocument(bytes32,bytes32)(bool)' $documentId $otherHash --rpc-url $env:SEPOLIA_RPC_URL
```

#### 4.3. Mô phỏng đăng ký trùng, không gửi transaction bị revert

Chạy chung mô phỏng: `owner()` trả địa chỉ sender, rồi `cast call` mô phỏng lại `registerDocumentWithLineage` với cùng bốn tham số. Kỳ vọng revert `DocumentAlreadyRegistered`. CALL không gửi transaction, không tốn gas; `--from` chỉ chọn sender mô phỏng.

**Output dự kiến:** lỗi revert có tên hoặc selector tương ứng `DocumentAlreadyRegistered(bytes32)`. Ví dụ cách biểu diễn, phần ID phụ thuộc proof:

```text
Error: ... execution reverted: DocumentAlreadyRegistered(0x<documentId>)
```

CLI exit code khác 0 là **mong đợi ở bài test này**. Một số RPC chỉ trả dữ liệu revert dạng hex thay vì tên custom error. Proof cũ không đổi; vì dùng `cast call`, không có transaction mới hay phí gas bị trừ.

```powershell
# Chạy khối này theo hướng dẫn phía trên
$currentOwner = cast call $registryAddress 'owner()(address)' --rpc-url $env:SEPOLIA_RPC_URL
if ($LASTEXITCODE -ne 0) { throw 'Không đọc được owner.' }

cast call $registryAddress 'registerDocumentWithLineage(bytes32,bytes32,bytes32,uint8)' $documentId $documentHash $caseId $documentKind `
    --from $currentOwner `
    --rpc-url $env:SEPOLIA_RPC_URL
```

Lỗi tại bài 4.3 là kết quả mong đợi. Đọc lại documents(id) phải thấy proof cũ không đổi.
### 5. Dữ liệu cần giữ cho bước tích hợp

Backend lưu chain ID, registry address, documentId, SHA-256, caseId, documentKind, tx hash, block number và trạng thái xác nhận. Có tx hash chưa đủ: kiểm tra receipt thành công, đúng registry/event và proof on-chain, rồi xử lý độ xác nhận theo network. Job blockchain tách khỏi việc ký để RPC lỗi không làm mất hợp đồng đã ký.

### 6. Lưu metadata để kiểm tra lại ở terminal mới

JSON ở bước 3.2 đã lưu metadata public trước khi gửi proof. Giữ file đó để kiểm tra lại sau khi đóng terminal.

Metadata đã được lưu ở bước 3.2 trước khi gửi transaction. Giữ file proof-ID.json trong thư mục repo; không cần tạo ID mới để lưu hoặc kiểm tra proof cũ.

Lưu thêm transaction hash và block number từ receipt cùng hồ sơ này. Khi mở terminal mới, chạy bước 1 để nạp RPC/account rồi đọc file metadata:

Thay đường dẫn JSON và PDF rồi chạy chung khối khôi phục biến. Chạy tiếp getter/verify, không tạo ID hoặc đăng ký lại.

**Output dự kiến:** không in gì nếu JSON hợp lệ; các biến contract address, ID, hash và đường dẫn PDF được khôi phục trong terminal. Sau đó gọi getter/verify sẽ cho output như bước 3.4 và 4.1. Nếu chainId trong metadata khác 11155111, khối ném lỗi.

```powershell
# Chạy khối này theo hướng dẫn phía trên
$saved = Get-Content -LiteralPath 'D:\duong-dan\proof-ID.json' -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if ($saved.chainId -ne 11155111) { throw 'Metadata không thuộc Sepolia.' }
$registryAddress = $saved.registryAddress
$documentId = $saved.documentId
$documentHash = $saved.documentHash

$pdfPath = 'D:\duong-dan\hop-dong-da-ky.pdf'
```

Nếu đã đăng ký mà chưa lưu JSON, dùng biến ở terminal cũ để lưu, hoặc đối chiếu documentId/hash từ event transaction đã ghi nhận. Không deploy lại hoặc tạo ID mới để tìm proof cũ.

### 7. Checklist kết quả

| Bài kiểm tra | Kết quả cần có |
|---|---|
| cast code | Có bytecode tại đúng địa chỉ contract |
| owner() | Khớp ví có quyền ghi |
| registerDocument | Receipt status 1, đúng from/to/event |
| documents(id) | Đúng hash đã gửi và timestamp ghi nhận |
| PDF gốc tính lại SHA-256 | verifyDocument trả true |
| PDF khác bytes, cùng ID | false |
| ID chưa tồn tại với hash zero | false |
| Đăng ký trùng bằng mô phỏng | Revert, proof cũ không đổi |

Không cần trả gas để đọc/verify. Chỉ bước cast send ghi proof gửi transaction thật. Hash khớp không thay thế kiểm tra chữ ký số, quyền sở hữu nhà hay chứng từ ngân hàng.
