# HomeSpace — Contract Document Registry

Ghi nhận và kiểm tra hash PDF hợp đồng đã ký, dùng stack quen thuộc từ crowdfunding: **Foundry + Solidity + OpenZeppelin + Sepolia + Alchemy + Etherscan**. Bạn tự chạy các lệnh deploy/gửi transaction bên dưới; repo không tự deploy.

## Contract và dữ liệu

`ContractDocumentRegistry` cho owner đăng ký một lần `documentId → documentHash + registeredAt`. Không có update/delete, giữ tiền, NFT hoặc logic thanh toán.

| ABI | Ý nghĩa |
|---|---|
| `registerDocument(bytes32,bytes32)` | Owner ghi proof; từ chối ID/hash zero hoặc ID đã tồn tại |
| `documents(bytes32)` | Trả `(bytes32 documentHash,uint256 registeredAt)`; ID chưa tồn tại trả zero |
| `verifyDocument(bytes32,bytes32)` | ID tồn tại và hash khớp mới trả `true` |
| `owner()`, `pendingOwner()` | Owner hiện tại và owner chờ nhận quyền |
| `transferOwnership(address)`, `acceptOwnership()` | Chuyển quyền ghi qua hai bước OpenZeppelin |

Event `DocumentRegistered` chứa ID, hash, địa chỉ ghi và timestamp block. `registeredAt` **không phải** thời điểm ký SmartCA.

- `documentId`: mã ngẫu nhiên opaque `bytes32` cho **một file PDF**. Backend lưu liên kết với `ContractDocument.id`, contract và revision trong database. Không dùng CCCD, email hoặc tài khoản ngân hàng làm ID public.
- `documentHash`: SHA-256 của **đúng bytes PDF `SIGNED_FINAL`**, không phải JSON, URL hoặc PDF render lại. Contract nhận hash do owner cung cấp; nó không tự đọc file hay chứng minh nội dung hợp đồng đúng.
- PDF và thông tin cá nhân giữ ở storage private. Phụ lục/phiên bản mới sau này có proof riêng, giữ proof cũ.
- Retry gặp `DocumentAlreadyRegistered`: đọc `documents(id)` và so sánh hash; không đổi ID để che một lần retry. Hash snapshot hiện có trong backend không phải hash PDF.

## 1. Kiểm tra local

Mở PowerShell tại repo đã có, không chạy lại `forge init`:

```powershell
Set-Location D:\Workspace\homespace\hs-smart-contract-blockchain
forge --version
cast --version
forge build
forge test -vv
forge fmt --check
```

Cấu hình giữ nguyên: Solidity `0.8.30`, EVM `cancun`, optimizer `200`. `foundry.lock` pin `forge-std v1.17.0` và `openzeppelin-contracts v5.7.0`. Chỉ khi clone mới và **thiếu** thư viện trong `lib/`, cài trước khi build:

```powershell
forge install foundry-rs/forge-std@v1.17.0 --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 --no-git
```

Repo giữ thư viện dưới `lib/` dạng source local được gitignore; dùng `--no-git` để không tạo submodule mới.

Nếu gặp `lib/forge-std already exists and is not a valid git repo`, kiểm tra source thay vì cài lại:

```powershell
Test-Path -LiteralPath lib/forge-std/src/Test.sol
Test-Path -LiteralPath lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol
```

Nếu cả hai trả `True` và `forge test --offline -vv` chạy được, bỏ qua bước install và tiếp tục. Thư mục thư viện có thể còn file `.git` trỏ tới metadata submodule không tồn tại; compiler vẫn dùng source bình thường. Không cần xóa thư viện để xử lý lỗi install này.

Tests dùng EVM local của Forge, không gửi transaction testnet. Test deploy script chỉ mô phỏng chain ID, không phải deploy Sepolia.

## 2. Keystore và cấu hình Sepolia

Chuẩn bị ví testnet riêng có Sepolia ETH trả gas, endpoint **Ethereum Sepolia** trên Alchemy và API key Etherscan. Không dùng ví có tài sản thật.

Giống crowdfunding, import ví bằng prompt tương tác vào keystore mã hóa. Nếu đã có account `sepoliaKey`, bỏ qua:

```powershell
cast wallet import sepoliaKey --interactive
```

Nếu Cast báo `Keystore file already exists .../sepoliaKey`, account đã tồn tại: không import lại hoặc ghi đè. Dùng account hiện có để lấy địa chỉ public:

```powershell
cast wallet address --account sepoliaKey
```

Nhập mật khẩu keystore khi được hỏi. Nếu không nhớ mật khẩu, giữ nguyên file keystore; chỉ tạo alias mới khi đã có ví testnet khác mà bạn kiểm soát.

Chỉ nhập private key tại prompt của Cast; không đặt key trong `.env`, source hoặc lệnh CLI. Không commit keystore.

```powershell
if (-not (Test-Path -LiteralPath .env)) { Copy-Item .env.example .env }
notepad .env
```

Điền `SEPOLIA_RPC_URL`, `ETHERSCAN_API_KEY` và `ACCOUNT=sepoliaKey`, không có dấu nháy hay comment cuối dòng. `ACCOUNT` là tên keystore đã import, không phải private key hoặc địa chỉ ví. Không cần khai báo `REGISTRY_OWNER` trong `.env`; bước dưới lấy địa chỉ public từ keystore và đặt biến này trong phiên PowerShell. `.env` đã được gitignore.

PowerShell không tự nạp `.env` vào `$env:`. Chạy nguyên khối sau; nó chỉ đọc cấu hình và kiểm tra, không gửi transaction. `ConvertFrom-StringData` đọc các dòng `KEY=value` và comment `#`, không thực thi nội dung file:

```powershell
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

```powershell
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
$registryAddress = '0xDIA_CHI_CONTRACT_VUA_DEPLOY'
```

Tra transaction và tab Contract trên [Sepolia Etherscan](https://sepolia.etherscan.io/). Verify source đối chiếu bytecode với Solidity, khác với `verifyDocument` kiểm tra hash PDF.

Nếu deploy thành công nhưng verify source thất bại, **không deploy lại**. Dùng đúng địa chỉ contract, owner constructor và cấu hình compiler ban đầu:

```powershell
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

## 4. Đọc contract và thử với PDF

Các lệnh đọc không tốn gas:

```powershell
cast code $registryAddress --rpc-url $env:SEPOLIA_RPC_URL
cast call $registryAddress 'owner()(address)' --rpc-url $env:SEPOLIA_RPC_URL
```

Bytecode phải khác `0x`; owner phải khớp địa chỉ cấu hình. Chọn PDF thử nghiệm trên máy, tạo documentId **một lần** và lưu lại trước khi gửi. Giữ ID này khi kiểm tra/retry:

```powershell
$pdfPath = 'D:\duong-dan\hop-dong-da-ky.pdf'
$documentId = cast keccak ([guid]::NewGuid().ToString())
if ($LASTEXITCODE -ne 0) { throw 'Không tạo được documentId.' }
$documentHash = '0x' + (Get-FileHash -LiteralPath $pdfPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()

# Lưu documentId, documentHash và registryAddress trước khi gửi.
# Lệnh này gửi transaction và tốn Sepolia ETH của owner.
cast send $registryAddress 'registerDocument(bytes32,bytes32)' $documentId $documentHash `
    --rpc-url $env:SEPOLIA_RPC_URL `
    --chain sepolia `
    --account $env:ACCOUNT
if ($LASTEXITCODE -ne 0) { throw 'Gửi proof thất bại; đọc proof trước khi retry.' }

cast call $registryAddress 'documents(bytes32)(bytes32,uint256)' $documentId `
    --rpc-url $env:SEPOLIA_RPC_URL
cast call $registryAddress 'verifyDocument(bytes32,bytes32)(bool)' $documentId $documentHash `
    --rpc-url $env:SEPOLIA_RPC_URL
```

Kết quả phải là `true`. Tính SHA-256 của một PDF khác/đã sửa rồi gọi `verifyDocument` với **cùng documentId**: kết quả phải là `false`. ID chưa tồn tại và hash zero cũng phải trả `false`:

```powershell
$unknownId = cast keccak ([guid]::NewGuid().ToString())
$zeroHash = '0x' + ('0' * 64)
cast call $registryAddress 'verifyDocument(bytes32,bytes32)(bool)' $unknownId $zeroHash `
    --rpc-url $env:SEPOLIA_RPC_URL
```

Backend tích hợp sau cần lưu chain ID, registry address, documentId, SHA-256, tx hash, block number và trạng thái xác nhận. Có tx hash chưa đủ: kiểm tra receipt thành công, đúng registry/event và proof on-chain, rồi xử lý độ xác nhận theo network. Job blockchain cần tách khỏi việc ký để RPC lỗi không làm mất hợp đồng đã ký.

## Quyền ghi và giới hạn

- Chỉ owner ghi; ai cũng đọc được. Khóa owner là nguồn xác nhận đầu vào, cần bảo vệ như khóa backend.
- Đổi ví bằng `transferOwnership(newOwner)`, sau đó ví mới gọi `acceptOwnership()`. Proof cũ giữ nguyên; owner cũ mất quyền ghi khi owner mới chấp nhận.
- **Không gọi `renounceOwnership()`**: hàm OpenZeppelin kế thừa này đặt owner bằng zero và vĩnh viễn ngừng ghi proof mới; proof cũ vẫn đọc được.
- Không lưu PII, PDF hoặc URL private trên public chain. Hash không chứng minh quyền sở hữu nhà, tiền đã chuyển hoặc giá trị pháp lý của hợp đồng; vẫn cần kiểm tra chữ ký số.
- Feature hiện chỉ ở smart contract; chưa tích hợp backend/frontend, chưa có escrow hay thanh toán crypto.

Tài liệu: [Foundry](https://getfoundry.sh/), [OpenZeppelin access control](https://docs.openzeppelin.com/contracts/5.x/access-control), [Ethereum networks](https://ethereum.org/en/developers/docs/networks/), [Etherscan verification](https://docs.etherscan.io/contract-verification/verify-with-foundry).
