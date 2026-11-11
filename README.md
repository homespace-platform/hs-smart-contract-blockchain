# HomeSpace — Smart Contracts

Registry ghi nhận hash PDF hợp đồng đã ký; EthPayment xử lý thanh toán gói hội viên bằng Sepolia ETH. Cả hai dùng **Foundry + Solidity + OpenZeppelin + Sepolia**. Bạn tự chạy các lệnh trong tài liệu triển khai và kiểm tra; repo không tự deploy.

## Contract và dữ liệu

`ContractDocumentRegistry` cho owner đăng ký một lần `documentId → documentHash + registeredAt`. Không có update/delete, giữ tiền, NFT hoặc logic thanh toán.

| ABI | Ý nghĩa |
|---|---|
| `registerDocumentWithLineage(bytes32,bytes32,bytes32,uint8)` | Owner ghi proof cùng mã hồ sơ và loại văn bản: 1=cọc, 2=thuê, 3=phụ lục |
| `caseIds(bytes32)`, `documentKinds(bytes32)` | Đọc mã hồ sơ và loại văn bản của một proof |
| `caseDeposits(bytes32)`, `caseLeases(bytes32)` | Đọc ID HĐ cọc/HĐ thuê duy nhất của hồ sơ; phụ lục cùng `caseId` thuộc HĐ thuê này |
| `registerDocument(bytes32,bytes32)` | Hàm cũ để thử proof đơn lẻ; không ghi quan hệ hồ sơ |
| `documents(bytes32)` | Trả `(bytes32 documentHash,uint256 registeredAt)`; ID chưa tồn tại trả zero |
| `verifyDocument(bytes32,bytes32)` | ID tồn tại và hash khớp mới trả `true` |
| `owner()`, `pendingOwner()` | Owner hiện tại và owner chờ nhận quyền |
| `transferOwnership(address)`, `acceptOwnership()` | Chuyển quyền ghi qua hai bước OpenZeppelin |

Event `DocumentRegistered` chứa ID, hash, địa chỉ ghi và timestamp block. `registeredAt` **không phải** thời điểm ký SmartCA.
Event `DocumentLineageRegistered` cho phép lọc các tài liệu theo `caseId` trên chain; trường `documentKind` phân biệt cọc/thuê/phụ lục.

- `documentId`: mã ngẫu nhiên opaque `bytes32` cho **một file PDF**. Backend lưu liên kết với `ContractDocument.id`, contract và revision trong database. Không dùng CCCD, email hoặc tài khoản ngân hàng làm ID public.
- `documentHash`: SHA-256 của **đúng bytes PDF `SIGNED_FINAL`**, không phải JSON, URL hoặc PDF render lại. Contract nhận hash do owner cung cấp; nó không tự đọc file hay chứng minh nội dung hợp đồng đúng.
- `caseId`: SHA-256 của chuỗi `homespace:case:<rentalRequestId>`; ba loại PDF của cùng yêu cầu thuê dùng chung mã này. `documentKind` phân biệt cọc (1), thuê (2), phụ lục (3). Registry chỉ cho một HĐ cọc và một HĐ thuê trong mỗi `caseId`; phụ lục chỉ ghi được sau HĐ thuê, nên có thể tra HĐ gốc qua `caseLeases(caseId)`. Backend vẫn quản lý trạng thái ký và ngày có hiệu lực.
- PDF và thông tin cá nhân giữ ở storage private. Phụ lục/phiên bản mới sau này có proof riêng, giữ proof cũ.
- Retry gặp `DocumentAlreadyRegistered`: đọc `documents(id)` và so sánh hash; không đổi ID để che một lần retry. Hash snapshot hiện có trong backend không phải hash PDF.

## Hướng dẫn thực hành

Chạy theo thứ tự, dùng PowerShell tại thư mục `hs-smart-contract-blockchain`:

1. [ContractDocumentRegistry](CONTRACT_DOCUMENT_REGISTRY.md): deploy, verify source, kiểm tra bytecode/owner và proof PDF sau deploy.
2. [EthPayment](ETH_PAYMENT.md): deploy, kiểm tra contract, thử thanh toán và đối chiếu ABI.

Hai contract có địa chỉ riêng; backend cấu hình từng địa chỉ bằng biến môi trường tương ứng.

Mỗi bước giải thích mục đích, hàm Solidity, tham số và output dự kiến trước khối PowerShell; trong khối chỉ giữ comment tổng quát. Output có ví dụ minh họa, cách đọc kết quả và phân biệt lỗi với trường hợp thành công không in gì. Các lệnh cùng bước được gom để chạy chung; phần nhập giá trị, gửi transaction và đọc kết quả được tách riêng. Tài liệu test có cách lưu proof để mở terminal mới kiểm tra lại.

Các lệnh `cast send` trong bài test gửi transaction và tốn Sepolia ETH. Các lệnh `cast code`/`cast call` chỉ đọc, không tốn gas.

## Quyền ghi và giới hạn

- Chỉ owner ghi; ai cũng đọc được. Khóa owner là nguồn xác nhận đầu vào, cần bảo vệ như khóa backend.
- Đổi ví bằng `transferOwnership(newOwner)`, sau đó ví mới gọi `acceptOwnership()`. Proof cũ giữ nguyên; owner cũ mất quyền ghi khi owner mới chấp nhận.
- **Không gọi `renounceOwnership()`**: hàm OpenZeppelin kế thừa này đặt owner bằng zero và vĩnh viễn ngừng ghi proof mới; proof cũ vẫn đọc được.
- Không lưu PII, PDF hoặc URL private trên public chain. Hash không chứng minh quyền sở hữu nhà, tiền đã chuyển hoặc giá trị pháp lý của hợp đồng; vẫn cần kiểm tra chữ ký số.
- Backend dùng `registerDocumentWithLineage` cho PDF ký đủ sau khi cấu hình **địa chỉ registry mới**. Registry cũ không hỗ trợ ABI này; phải deploy lại rồi cập nhật `CONTRACT_DOCUMENT_REGISTRY_ADDRESS` thủ công. Registry không giữ ETH; thanh toán gói hội viên dùng `EthPayment` riêng.

Tài liệu: [Foundry](https://getfoundry.sh/), [OpenZeppelin access control](https://docs.openzeppelin.com/contracts/5.x/access-control), [Ethereum networks](https://ethereum.org/en/developers/docs/networks/), [Etherscan verification](https://docs.etherscan.io/contract-verification/verify-with-foundry).
