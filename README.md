Tạo **project mới tại local**, bạn tự chạy trong PowerShell:

```powershell
cd D:\Workspace\homespace

# Tạo project Foundry mới
forge init hs-smart-contract-blockchain --offline

cd hs-smart-contract-blockchain

# Cài thư viện
forge install foundry-rs/forge-std@v1.17.0
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0
```

Sửa file `foundry.toml`:

```toml
[profile.default]
src = "src"
test = "test"
script = "script"
out = "out"
libs = ["lib"]

solc = "0.8.30"
evm_version = "cancun"
optimizer = true
optimizer_runs = 200
```

Tạo file `remappings.txt` tại thư mục gốc project:

```text
forge-std/=lib/forge-std/src/
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
```

Hai thư viện đã cài gồm:

- **forge-std:** phục vụ test và script triển khai.
- **OpenZeppelin Contracts:** phục vụ phân quyền, chữ ký và các contract chuẩn.

**Bạn đã khởi tạo đúng.** Mình đã kiểm tra:

| Thành phần | Kết quả |
|---|---|
| Cấu trúc `src/`, `test/`, `script/`, `lib/` | Đúng chuẩn Foundry |
| [foundry.toml](D:/Workspace/homespace/hs-smart-contract-blockchain/foundry.toml) | Solidity `0.8.30`, EVM `cancun`, optimizer `200` — đúng |
| [remappings.txt](D:/Workspace/homespace/hs-smart-contract-blockchain/remappings.txt) | Đúng đường dẫn hai thư viện |
| `forge-std` | Đã cài đúng `v1.17.0` |
| OpenZeppelin Contracts | Đã cài đúng `v5.7.0` |
| `foundry.lock` | Khớp với commit thư viện thực tế |

Các file `Counter` là ví dụ mặc định. Dòng `pragma solidity ^0.8.13` trong đó **vẫn tương thích với compiler 0.8.30**, không phải lỗi.

Mình **chưa chạy build/test và không sửa file**. Bạn có thể tự kiểm tra tiếp:

```powershell
cd D:\Workspace\homespace\hs-smart-contract-blockchain

forge build
forge test -vv
forge fmt --check
```