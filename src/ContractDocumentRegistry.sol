// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice Lưu và đối chiếu hash PDF do owner cung cấp; mỗi tài liệu chỉ được đăng ký một lần.
/// @dev PDF và dữ liệu cá nhân nằm ngoài blockchain. Hash khớp không tự chứng minh chữ ký số hợp lệ.
// Ownable cung cấp owner()/onlyOwner; Ownable2Step yêu cầu ví mới acceptOwnership() khi chuyển quyền.
// Đây là hàm kế thừa nên không thấy khai báo lại trong contract này.
contract ContractDocumentRegistry is Ownable2Step {
    // Một bằng chứng gồm hash file và thời điểm blockchain ghi nhận, không chứa nội dung PDF.
    struct DocumentProof {
        // SHA-256 của đúng bytes PDF cuối cùng, được tính ở backend hoặc bằng Get-FileHash.
        bytes32 documentHash;
        // Unix timestamp giây của block ghi proof, không phải thời điểm hai bên ký hợp đồng.
        uint256 registeredAt;
    }

    // Custom error giúp CLI/backend phân biệt nguyên nhân transaction bị revert.
    error InvalidDocumentId();
    error InvalidDocumentHash();
    error DocumentAlreadyRegistered(bytes32 documentId);

    // Event để ứng dụng tra lịch sử: indexed đưa ID/hash/người ghi vào topics của log.
    // recorder là ví gửi transaction; registeredAt nằm trong phần data của log.
    event DocumentRegistered(
        bytes32 indexed documentId, bytes32 indexed documentHash, address indexed recorder, uint256 registeredAt
    );

    // Key là mã riêng của tài liệu/phiên bản, không phải địa chỉ ví hoặc hash PDF.
    // public khiến compiler tự sinh documents(id) trả (documentHash, registeredAt).
    // ID chưa có trả hai giá trị zero; không có hàm cập nhật hoặc xóa proof đã ghi.
    mapping(bytes32 documentId => DocumentProof proof) public documents;

    /// @param initialOwner Ví có quyền ghi proof, lấy từ keystore ACCOUNT khi deploy.
    // Constructor chỉ chạy lúc tạo contract; Ownable từ chối owner là địa chỉ zero.
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Ghi proof mới. Gọi bằng cast send sẽ gửi transaction và owner trả gas.
    /// @param documentId Mã bytes32 không chứa thông tin cá nhân; phụ lục/phiên bản mới dùng ID riêng.
    /// @param documentHash SHA-256 của đúng bytes PDF cần chứng thực, được tính ngoài blockchain.
    // onlyOwner kiểm tra msg.sender trước khi chạy thân hàm; ví khác bị từ chối.
    function registerDocument(bytes32 documentId, bytes32 documentHash) external onlyOwner {
        // Không nhận zero để phân biệt rõ proof hợp lệ với phần tử mapping chưa tồn tại.
        if (documentId == bytes32(0)) revert InvalidDocumentId();
        if (documentHash == bytes32(0)) revert InvalidDocumentHash();
        // Cấm ghi đè cả khi gửi lại cùng hash; retry cần đọc proof cũ trước.
        if (documents[documentId].documentHash != bytes32(0)) revert DocumentAlreadyRegistered(documentId);

        // Lưu trạng thái on-chain, sau đó phát log cho ứng dụng theo dõi transaction.
        documents[documentId] = DocumentProof(documentHash, block.timestamp);
        emit DocumentRegistered(documentId, documentHash, msg.sender, block.timestamp);
    }

    /// @notice Đối chiếu hash với proof đã ghi; cast call chỉ đọc, không gửi transaction hay trả gas.
    /// @param documentId ID đã dùng lúc đăng ký, giữ nguyên khi kiểm tra file khác hoặc retry.
    /// @param documentHash Hash tính lại từ PDF đang kiểm tra, không phải transaction hash.
    /// @return True khi ID đã tồn tại và hash khớp; false khi chưa có proof hoặc file khác hash.
    function verifyDocument(bytes32 documentId, bytes32 documentHash) external view returns (bool) {
        bytes32 storedHash = documents[documentId].documentHash;
        // Điều kiện khác zero ngăn ID chưa đăng ký + hash zero bị hiểu nhầm là khớp.
        return storedHash != bytes32(0) && storedHash == documentHash;
    }
}
