# Deploy ContractDocumentRegistry lên Sepolia

Hướng dẫn deploy thủ công bằng PowerShell, dùng Foundry, keystore `ACCOUNT`, Alchemy và Etherscan. Các lệnh có `--broadcast` chỉ được gửi khi bạn tự chạy.

[Tổng quan contract](README.md) · [Test sau khi deploy](POST_DEPLOY_TEST.md)

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

## Bước tiếp theo

Lưu địa chỉ contract (`Deployed to`), transaction hash, chain ID `11155111` và địa chỉ owner ban đầu. Giữ cấu hình compiler để có thể verify source lại.

Tiếp tục [Test sau khi deploy](POST_DEPLOY_TEST.md). Không chạy lại lệnh deploy để kiểm tra contract đã có.
