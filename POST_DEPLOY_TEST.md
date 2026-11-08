# Test sau khi deploy ContractDocumentRegistry

Dùng địa chỉ contract đã deploy ở [DEPLOY.md](DEPLOY.md). Tài liệu này không tạo contract mới. Phần ghi proof gửi transaction và tốn Sepolia ETH; phần đọc/đối chiếu không tốn gas.

## 1. Chuẩn bị phiên PowerShell

Nếu mở terminal mới, nạp lại RPC và tên keystore từ `.env`. Không cần Etherscan API key cho các bài test này. Thay địa chỉ mẫu bằng giá trị `Deployed to`, không dùng địa chỉ ví:

```powershell
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

$registryAddress = '0xDIA_CHI_CONTRACT_DA_DEPLOY'
```

Nếu có lỗi ở bước chuẩn bị, xử lý xong trước khi chạy tiếp.

## 2. Kiểm tra contract và owner

Các lệnh đọc không tốn gas:

```powershell
cast code $registryAddress --rpc-url $env:SEPOLIA_RPC_URL
cast call $registryAddress 'owner()(address)' --rpc-url $env:SEPOLIA_RPC_URL
```

- `cast code`: đọc bytecode tại địa chỉ contract; chuỗi dài `0x6080...` là có code, chỉ `0x` là không có code trên mạng đang kiểm tra.
- `cast call ... owner()`: đọc địa chỉ ví hiện có quyền ghi hash. Kết quả phải khớp ví owner đã cấu hình khi deploy, hoặc owner mới nếu bạn đã chuyển quyền.
- Cả hai lệnh trên chỉ đọc dữ liệu, không gửi transaction. Có bytecode chưa đủ để xác nhận đó là đúng contract; đối chiếu thêm địa chỉ và source đã verify trên Etherscan.

## 3. Ghi hash PDF và kiểm tra khớp

Chọn PDF thử nghiệm trên máy, tạo documentId **một lần** và lưu lại trước khi gửi. Giữ ID này khi kiểm tra/retry:

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

Kết quả phải là `true`.

## 4. Kiểm tra file khác và ID chưa tồn tại

Tính SHA-256 của một PDF khác/đã sửa rồi gọi `verifyDocument` với **cùng documentId**: kết quả phải là `false`. ID chưa tồn tại và hash zero cũng phải trả `false`:

```powershell
$unknownId = cast keccak ([guid]::NewGuid().ToString())
$zeroHash = '0x' + ('0' * 64)
cast call $registryAddress 'verifyDocument(bytes32,bytes32)(bool)' $unknownId $zeroHash `
    --rpc-url $env:SEPOLIA_RPC_URL
```

## 5. Dữ liệu cần giữ cho bước tích hợp

Backend tích hợp sau cần lưu chain ID, registry address, documentId, SHA-256, tx hash, block number và trạng thái xác nhận. Có tx hash chưa đủ: kiểm tra receipt thành công, đúng registry/event và proof on-chain, rồi xử lý độ xác nhận theo network. Job blockchain cần tách khỏi việc ký để RPC lỗi không làm mất hợp đồng đã ký.
