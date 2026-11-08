# HomeSpace — Contract Document Registry

Ghi nhận và kiểm tra hash PDF hợp đồng đã ký, dùng stack quen thuộc từ crowdfunding: **Foundry + Solidity + OpenZeppelin + Sepolia + Alchemy + Etherscan**. Bạn tự chạy các lệnh trong tài liệu deploy và kiểm tra; repo không tự deploy.

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

## Hướng dẫn thực hành

Chạy theo thứ tự, dùng PowerShell tại thư mục `hs-smart-contract-blockchain`:

1. [Deploy lên Sepolia](DEPLOY.md): kiểm tra local, cấu hình `ACCOUNT`, deploy và verify source trên Etherscan.
2. [Test sau khi deploy](POST_DEPLOY_TEST.md): kiểm tra bytecode/owner, ghi hash PDF và kiểm tra kết quả đúng/sai.

Mỗi bước giải thích mục đích, hàm Solidity, tham số và output dự kiến trước khối PowerShell; trong khối chỉ giữ comment tổng quát. Output có ví dụ minh họa, cách đọc kết quả và phân biệt lỗi với trường hợp thành công không in gì. Các lệnh cùng bước được gom để chạy chung; phần nhập giá trị, gửi transaction và đọc kết quả được tách riêng. Tài liệu test có cách lưu proof để mở terminal mới kiểm tra lại.

Các lệnh `cast send` trong bài test gửi transaction và tốn Sepolia ETH. Các lệnh `cast code`/`cast call` chỉ đọc, không tốn gas.

## Quyền ghi và giới hạn

- Chỉ owner ghi; ai cũng đọc được. Khóa owner là nguồn xác nhận đầu vào, cần bảo vệ như khóa backend.
- Đổi ví bằng `transferOwnership(newOwner)`, sau đó ví mới gọi `acceptOwnership()`. Proof cũ giữ nguyên; owner cũ mất quyền ghi khi owner mới chấp nhận.
- **Không gọi `renounceOwnership()`**: hàm OpenZeppelin kế thừa này đặt owner bằng zero và vĩnh viễn ngừng ghi proof mới; proof cũ vẫn đọc được.
- Không lưu PII, PDF hoặc URL private trên public chain. Hash không chứng minh quyền sở hữu nhà, tiền đã chuyển hoặc giá trị pháp lý của hợp đồng; vẫn cần kiểm tra chữ ký số.
- Feature hiện chỉ ở smart contract; chưa tích hợp backend/frontend, chưa có escrow hay thanh toán crypto.

Tài liệu: [Foundry](https://getfoundry.sh/), [OpenZeppelin access control](https://docs.openzeppelin.com/contracts/5.x/access-control), [Ethereum networks](https://ethereum.org/en/developers/docs/networks/), [Etherscan verification](https://docs.etherscan.io/contract-verification/verify-with-foundry).
