# Test sau khi deploy ContractDocumentRegistry

Dùng địa chỉ contract đã deploy ở [DEPLOY.md](DEPLOY.md). Tài liệu này không tạo contract mới. Phần ghi proof gửi transaction và tốn Sepolia ETH; phần đọc/đối chiếu không tốn gas.

## Bản đồ CLI → Solidity

Cú pháp bên dưới là **PowerShell**, không phải Bash/CMD. Chạy từng khối và đọc kết quả. Xem [source registry](src/ContractDocumentRegistry.sol) song song với tài liệu này.

| Lệnh | Phần source được thực thi | Ghi blockchain / trả gas? |
|---|---|---|
| `cast code` | Đọc runtime bytecode, không gọi hàm Solidity | Không |
| `cast call ... owner()` | `owner()` kế thừa từ OpenZeppelin Ownable | Không |
| `cast send ... registerDocument(...)` | `registerDocument()` trong registry, chạy `onlyOwner` trước | Có |
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
## 1. Chuẩn bị phiên PowerShell

Nếu mở terminal mới, nạp lại RPC và tên keystore từ `.env`. Không cần Etherscan API key cho các bài test này. Thay địa chỉ mẫu bằng giá trị `Deployed to`, không dùng địa chỉ ví:

```powershell
# Chọn thư mục có .env. Biến của terminal cũ không tự có trong terminal mới.
Set-Location D:\Workspace\homespace\hs-smart-contract-blockchain

& {
    # Nạp cấu hình dạng dữ liệu, không thực thi .env.
    $config = Get-Content -LiteralPath .env -Raw -ErrorAction Stop | ConvertFrom-StringData -ErrorAction Stop
    $env:SEPOLIA_RPC_URL = $config.SEPOLIA_RPC_URL
    $env:ACCOUNT = $config.ACCOUNT
    if ([string]::IsNullOrWhiteSpace($env:SEPOLIA_RPC_URL) -or [string]::IsNullOrWhiteSpace($env:ACCOUNT)) {
        throw 'Điền SEPOLIA_RPC_URL và ACCOUNT trong .env.'
    }
    # Hỏi RPC về chain ID; chưa gọi contract.
    $chainId = cast chain-id --rpc-url $env:SEPOLIA_RPC_URL
    if ($LASTEXITCODE -ne 0 -or "$chainId".Trim() -ne '11155111') {
        throw 'RPC phải là Ethereum Sepolia (chain ID 11155111).'
    }
}

# Thay bằng Deployed to đã lưu, không dùng địa chỉ ví.
$registryAddress = '0xDIA_CHI_CONTRACT_DA_DEPLOY'
```

Nếu có lỗi ở bước chuẩn bị, xử lý xong trước khi chạy tiếp.

## 2. Kiểm tra contract và owner

Các lệnh đọc không tốn gas:

```powershell
# CHỈ ĐỌC: không gọi hàm Solidity; xem địa chỉ có runtime bytecode chưa.
# Kỳ vọng chuỗi dài 0x6080...; chỉ 0x là không có code trên mạng này.
cast code $registryAddress --rpc-url $env:SEPOLIA_RPC_URL
# CHỈ ĐỌC: gọi owner() kế thừa từ OpenZeppelin Ownable, trả address.
# Kỳ vọng khớp ví ACCOUNT có quyền ghi; không chạy constructor lại.
cast call $registryAddress 'owner()(address)' --rpc-url $env:SEPOLIA_RPC_URL
```

- `cast code`: đọc bytecode tại địa chỉ contract; chuỗi dài `0x6080...` là có code, chỉ `0x` là không có code trên mạng đang kiểm tra.
- `cast call ... owner()`: đọc địa chỉ ví hiện có quyền ghi hash. Kết quả phải khớp ví owner đã cấu hình khi deploy, hoặc owner mới nếu bạn đã chuyển quyền.
- Cả hai lệnh trên chỉ đọc dữ liệu, không gửi transaction. Có bytecode chưa đủ để xác nhận đó là đúng contract; đối chiếu thêm địa chỉ và source đã verify trên Etherscan.

## 3. Ghi hash PDF và kiểm tra khớp

Chọn PDF thử nghiệm trên máy, tạo documentId **một lần** và lưu lại trước khi gửi. Giữ ID này khi kiểm tra/retry:

```powershell
# Chọn file thật; lệnh sau chỉ đọc file, không upload PDF lên chain.
$pdfPath = 'D:\duong-dan\hop-dong-da-ky.pdf'
# Tạo GUID ngẫu nhiên, hash bằng Keccak để được ID bytes32.
# Không phải hash PDF. Chỉ chạy khi tạo proof MỚI; giữ ID cũ khi verify.
$documentId = cast keccak ([guid]::NewGuid().ToString())
if ($LASTEXITCODE -ne 0) { throw 'Không tạo được documentId.' }
# SHA-256 của đúng bytes file trên máy; thêm 0x để truyền bytes32.
# Không dùng Keccak thay SHA-256 cho documentHash trong flow này.
$documentHash = '0x' + (Get-FileHash -LiteralPath $pdfPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()

# Lưu documentId, documentHash và registryAddress trước khi gửi.
# Lệnh này gửi transaction và tốn Sepolia ETH của owner.
# Gọi registerDocument(documentId, documentHash), đúng thứ tự 2 tham số.
# --account: ví ký lệnh phải là owner; --rpc-url/--chain: mạng Sepolia.
# Không thêm --value: hàm này không nhận ETH, chỉ ví gửi trả gas.
cast send $registryAddress 'registerDocument(bytes32,bytes32)' $documentId $documentHash `
    --rpc-url $env:SEPOLIA_RPC_URL `
    --chain sepolia `
    --account $env:ACCOUNT
if ($LASTEXITCODE -ne 0) { throw 'Gửi proof thất bại; đọc proof trước khi retry.' }

# CHỈ ĐỌC: getter tự sinh từ mapping public documents, key là documentId.
# Trả hash rồi Unix timestamp giây; ID chưa có trả hash zero và timestamp 0.
cast call $registryAddress 'documents(bytes32)(bytes32,uint256)' $documentId `
    --rpc-url $env:SEPOLIA_RPC_URL
# CHỈ ĐỌC: gọi verifyDocument(id, hash), trả bool true/false.
# Không ghi hash mới và không thay đổi proof cũ.
cast call $registryAddress 'verifyDocument(bytes32,bytes32)(bool)' $documentId $documentHash `
    --rpc-url $env:SEPOLIA_RPC_URL
```

Kết quả phải là `true`.


### Solidity xử lý lời gọi ghi proof như thế nào?

```solidity
function registerDocument(bytes32 documentId, bytes32 documentHash) external onlyOwner {
    if (documentId == bytes32(0)) revert InvalidDocumentId();
    if (documentHash == bytes32(0)) revert InvalidDocumentHash();
    if (documents[documentId].documentHash != bytes32(0)) revert DocumentAlreadyRegistered(documentId);

    documents[documentId] = DocumentProof(documentHash, block.timestamp);
    emit DocumentRegistered(documentId, documentHash, msg.sender, block.timestamp);
}
```

Thứ tự: onlyOwner kiểm tra msg.sender → từ chối ID/hash zero → từ chối ID đã có → ghi mapping → phát event. Hàm không đọc PDF hoặc kiểm tra chữ ký SmartCA; owner cung cấp hash đầu vào.

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

### Đọc receipt sau cast send

| Trường | Ý nghĩa |
|---|---|
| status 1 (success) | Transaction thực thi thành công; status 0 là revert |
| from / to | Ví gửi / địa chỉ registry nhận lời gọi |
| transactionHash | Mã giao dịch để lưu và tra explorer |
| blockNumber / blockHash | Block chứa transaction |
| gasUsed / effectiveGasPrice | Gas thực dùng / đơn giá; tích hai số là phí thực thi tính bằng wei |
| contractAddress trống | Bình thường: đang gọi contract có sẵn, không deploy contract mới |
| logs | Event DocumentRegistered, không chứa PDF |

Với event của registry này: topics[0] là chữ ký event; topics[1], [2], [3] lần lượt là documentId, documentHash, recorder (address được đệm lên 32 byte). data chứa registeredAt. Timestamp là thời điểm block ghi nhận, không phải ngày ký hoặc thời gian sửa file.

Nếu CLI timeout sau khi gửi, đọc lại documents(id) trước khi retry. Cùng ID/hash đã có thì tiếp tục verify; khác hash thì dừng đối chiếu. Gửi lại cùng ID sẽ revert kể cả hash giống nhau.
## 4. Kiểm tra file khác và ID chưa tồn tại

Tính SHA-256 của một PDF khác/đã sửa rồi gọi `verifyDocument` với **cùng documentId**: kết quả phải là `false`. ID chưa tồn tại và hash zero cũng phải trả `false`:

```powershell
# ID mới chỉ để test chưa tồn tại; không đăng ký ID này.
$unknownId = cast keccak ([guid]::NewGuid().ToString())
# bytes32 zero: 0x và 64 ký tự 0.
$zeroHash = '0x' + ('0' * 64)
# CHỈ ĐỌC: gọi verifyDocument(id, hash), trả bool true/false.
# Không ghi hash mới và không thay đổi proof cũ.
cast call $registryAddress 'verifyDocument(bytes32,bytes32)(bool)' $unknownId $zeroHash `
    --rpc-url $env:SEPOLIA_RPC_URL
```


### 4.1. Kiểm tra lại PDF hiện tại thay vì chỉ dùng biến hash cũ

```powershell
# Tính lại từ file đang có trên máy; không tạo documentId mới.
$currentHash = '0x' + (Get-FileHash -LiteralPath $pdfPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()

# Gọi verifyDocument(id, currentHash); file gốc không đổi bytes -> true.
cast call $registryAddress 'verifyDocument(bytes32,bytes32)(bool)' $documentId $currentHash --rpc-url $env:SEPOLIA_RPC_URL
```

Nếu chỉ truyền biến documentHash cũ, bạn chưa thực sự kiểm tra bytes của PDF hiện tại.

### 4.2. Kiểm tra PDF khác bytes, giữ cùng ID

Chuẩn bị một PDF khác hoặc sửa một bản sao, giữ nguyên file gốc. Chỉ đổi tên file nhưng nội dung bytes không đổi thì hash vẫn giống và true là đúng.

```powershell
# Thay đường dẫn bằng PDF khác nội dung; không ghi đè bản gốc.
$otherPdfPath = 'D:\duong-dan\hop-dong-ban-sua.pdf'
$otherHash = '0x' + (Get-FileHash -LiteralPath $otherPdfPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
if ($otherHash -eq $documentHash) { throw 'Hai file cùng hash; chọn file khác nội dung.' }

# CHỈ ĐỌC: verifyDocument cùng ID, hash khác -> kỳ vọng false.
cast call $registryAddress 'verifyDocument(bytes32,bytes32)(bool)' $documentId $otherHash --rpc-url $env:SEPOLIA_RPC_URL
```

### 4.3. Mô phỏng đăng ký trùng, không gửi transaction bị revert

```powershell
# Đọc owner hiện tại để chọn sender cho mô phỏng.
$currentOwner = cast call $registryAddress 'owner()(address)' --rpc-url $env:SEPOLIA_RPC_URL
if ($LASTEXITCODE -ne 0) { throw 'Không đọc được owner.' }

# Dùng CALL, không dùng send: mô phỏng registerDocument với ID đã có.
# --from chỉ đặt sender cho mô phỏng, không ký hoặc cấp quyền gửi transaction thật.
# Kỳ vọng revert DocumentAlreadyRegistered(documentId), CLI exit code khác 0.
# Không lưu thay đổi và không tốn gas của một transaction bị revert.
cast call $registryAddress 'registerDocument(bytes32,bytes32)' $documentId $documentHash `
    --from $currentOwner `
    --rpc-url $env:SEPOLIA_RPC_URL
```

Lỗi tại bài 4.3 là kết quả mong đợi. Đọc lại documents(id) phải thấy proof cũ không đổi.
## 5. Dữ liệu cần giữ cho bước tích hợp

Backend tích hợp sau cần lưu chain ID, registry address, documentId, SHA-256, tx hash, block number và trạng thái xác nhận. Có tx hash chưa đủ: kiểm tra receipt thành công, đúng registry/event và proof on-chain, rồi xử lý độ xác nhận theo network. Job blockchain cần tách khỏi việc ký để RPC lỗi không làm mất hợp đồng đã ký.

## 6. Lưu metadata để kiểm tra lại ở terminal mới

Lưu sau khi tạo ID/hash, trước khi đóng terminal. JSON chỉ chứa metadata public, không chứa PDF, API key hoặc mật khẩu. File được ghi vào thư mục repo, tên theo documentId; bạn giữ file này để tra cứu lại.

```powershell
# Chỉ lưu trên máy, không gọi hàm Solidity.
$proofFile = Join-Path (Get-Location) ("proof-{0}.json" -f $documentId)
[ordered]@{
    chainId = 11155111
    registryAddress = $registryAddress
    documentId = $documentId
    documentHash = $documentHash
} | ConvertTo-Json | Set-Content -LiteralPath $proofFile -Encoding UTF8
```

Lưu thêm transaction hash và block number từ receipt cùng hồ sơ này. Khi mở terminal mới, chạy bước 1 để nạp RPC/account rồi đọc file metadata:

```powershell
# Thay bằng đường dẫn JSON đã lưu; không phải đường dẫn PDF.
$saved = Get-Content -LiteralPath 'D:\duong-dan\proof-ID.json' -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if ($saved.chainId -ne 11155111) { throw 'Metadata không thuộc Sepolia.' }
$registryAddress = $saved.registryAddress
$documentId = $saved.documentId
$documentHash = $saved.documentHash

# Chọn lại PDF và chạy phần getter/verify; không tạo ID hoặc đăng ký lại.
$pdfPath = 'D:\duong-dan\hop-dong-da-ky.pdf'
```

Nếu đã đăng ký mà chưa lưu JSON, dùng biến ở terminal cũ để lưu, hoặc đối chiếu documentId/hash từ event transaction đã ghi nhận. Không deploy lại hoặc tạo ID mới để tìm proof cũ.

## 7. Checklist kết quả

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
