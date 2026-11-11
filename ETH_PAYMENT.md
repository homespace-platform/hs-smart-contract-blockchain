# EthPayment — triển khai và kiểm tra trên Sepolia

`ContractDocumentRegistry.sol` và `EthPayment.sol` là **hai contract độc lập**, mỗi contract có địa chỉ riêng. Registry đang dùng để ghi hash PDF; EthPayment nhận ETH khi chủ nhà mua gói hội viên. Không thay `CONTRACT_DOCUMENT_REGISTRY_ADDRESS` bằng địa chỉ EthPayment.

Các lệnh dưới đây dành cho **PowerShell**. Chỉ bước `forge create --broadcast` gửi giao dịch và tốn Sepolia ETH. Repo hiện dùng `forge create` trong [hướng dẫn registry](CONTRACT_DOCUMENT_REGISTRY.md); script registry là cách deploy khác, không cần chạy thêm.

## 1. Chuẩn bị ví HomeSpace

- Dùng **cùng một ví HomeSpace** làm owner, quote signer và recipient. Ví này là keystore `ACCOUNT` đang dùng để deploy registry.
- Backend dùng private key của ví đó để ký báo giá; contract chuyển Sepolia ETH của người mua gói hội viên thẳng về địa chỉ công khai của cùng ví.

Chỉ dùng ví thử nghiệm trên Sepolia, không dùng ví chứa ETH Mainnet. Không ghi private key vào source, tài liệu, lệnh CLI hoặc ảnh chụp màn hình. Backend cần private key của ví này trong `.env` riêng để ký báo giá.

## 2. Kiểm tra local và mạng

Nếu đã tạo `.env` theo [hướng dẫn registry](CONTRACT_DOCUMENT_REGISTRY.md), giữ nguyên `SEPOLIA_RPC_URL` và `ACCOUNT`. PowerShell không tự nạp `.env`:

```powershell
Set-Location D:\Workspace\homespace\hs-smart-contract-blockchain
forge test --match-contract EthPaymentTest
$cfg = Get-Content -LiteralPath .env -Raw | ConvertFrom-StringData
$rpcUrl = $cfg.SEPOLIA_RPC_URL
$account = $cfg.ACCOUNT
if ([string]::IsNullOrWhiteSpace($rpcUrl) -or [string]::IsNullOrWhiteSpace($account) -or [string]::IsNullOrWhiteSpace($cfg.ETHERSCAN_API_KEY)) { throw 'Thiếu SEPOLIA_RPC_URL, ACCOUNT hoặc ETHERSCAN_API_KEY trong .env.' }
if ("$(cast chain-id --rpc-url $rpcUrl)".Trim() -ne '11155111') { throw 'RPC phải là Ethereum Sepolia.' }
$ownerAddress = "$(cast wallet address --account $account)".Trim()
if ($ownerAddress -notmatch '^0x[0-9a-fA-F]{40}$') { throw 'Địa chỉ ví không hợp lệ.' }
$signerAddress = $ownerAddress
cast balance $ownerAddress --ether --rpc-url $rpcUrl
```

Không cần tạo keystore `quoteSigner`. Xác nhận `$ownerAddress` là ví HomeSpace bạn muốn dùng trước khi deploy. Ví này cần Sepolia ETH để trả gas deploy.

## 3. Deploy và verify đúng một lần

Đọc lại `chain-id`, owner và signer ở bước 2 trước khi chạy. Constructor là `EthPayment(initialOwner, initialQuoteSigner)`. Lệnh này mở keystore để ký, gửi **một** giao dịch deploy và yêu cầu Etherscan verify source ngay sau đó, giống cách deploy registry. `--constructor-args` đặt cuối:

```powershell
forge create src/EthPayment.sol:EthPayment `
    --rpc-url $rpcUrl `
    --chain sepolia `
    --account $account `
    --broadcast `
    --verify `
    --verifier etherscan `
    --etherscan-api-key $cfg.ETHERSCAN_API_KEY `
    --constructor-args $ownerAddress $signerAddress
```

Lưu giá trị **`Deployed to`** làm địa chỉ EthPayment và lưu transaction hash. Nếu deploy thành công nhưng verify lỗi, **không chạy lại `forge create`**: mỗi lần chạy sẽ tạo contract mới. Dùng bước 5 để verify địa chỉ cũ.

## 4. Kiểm tra contract vừa deploy

Thay placeholder bằng đúng giá trị `Deployed to`:

```powershell
$ethPaymentAddress = '0xDIA_CHI_ETH_PAYMENT_VUA_DEPLOY'
if ($ethPaymentAddress -notmatch '^0x[0-9a-fA-F]{40}$') { throw 'Chưa điền địa chỉ contract.' }
cast call $ethPaymentAddress 'owner()(address)' --rpc-url $rpcUrl
cast call $ethPaymentAddress 'quoteSigner()(address)' --rpc-url $rpcUrl
cast code $ethPaymentAddress --rpc-url $rpcUrl
```

Hai địa chỉ phải lần lượt khớp `$ownerAddress` và `$signerAddress`; `cast code` phải trả bytecode khác `0x`. Tra địa chỉ trên [Sepolia Etherscan](https://sepolia.etherscan.io/). Xem [phần ABI bên dưới](#abi-và-chữ-ký-eip-712) để đối chiếu ABI và chữ ký EIP-712.

## 5. Verify lại khi deploy đã thành công nhưng verify lỗi

Chỉ dùng bước này cho contract **đã deploy** nhưng chưa được Etherscan verify, kể cả contract bạn vừa tạo trước khi tài liệu có `--verify`. Verify giúp mọi người xem source code và gọi các method trên Etherscan; contract vẫn hoạt động nếu chưa verify. Dùng đúng địa chỉ `Deployed to`, hai constructor arguments và cấu hình compiler của lần deploy. Lấy API key từ `.env` local, không in key ra màn hình:

```powershell
if ([string]::IsNullOrWhiteSpace($cfg.ETHERSCAN_API_KEY)) { throw 'Thiếu ETHERSCAN_API_KEY trong .env.' }
$constructorArgs = cast abi-encode 'constructor(address,address)' $ownerAddress $signerAddress
forge verify-contract $ethPaymentAddress src/EthPayment.sol:EthPayment `
    --chain sepolia `
    --verifier etherscan `
    --rpc-url $rpcUrl `
    --constructor-args $constructorArgs `
    --etherscan-api-key $cfg.ETHERSCAN_API_KEY `
    --watch
```

Sau khi hoàn tất, kiểm tra tab **Contract → Code** trên trang địa chỉ Sepolia Etherscan. Nếu verify báo sai bytecode/constructor, đối chiếu transaction deploy và cấu hình `foundry.toml`; không deploy lại chỉ để thử verify. [Foundry: verify-contract](https://getfoundry.sh/forge/).

## 6. Cấu hình backend

Trong **`D:\Workspace\homespace\hs-core-api\.env`** (file local, không commit), điền:

```dotenv
MEMBERSHIP_ETH_PAYMENT_RPC_URL=<cùng RPC Sepolia đã kiểm tra ở bước 2>
MEMBERSHIP_ETH_PAYMENT_CONTRACT_ADDRESS=<Deployed to của EthPayment>
MEMBERSHIP_ETH_PAYMENT_QUOTE_SIGNER_PRIVATE_KEY=<private key của ví ACCOUNT/HomeSpace>
MEMBERSHIP_ETH_PAYMENT_RECIPIENT_ADDRESS=<địa chỉ công khai $ownerAddress của cùng ví>
```

| Biến | Điền gì? |
|---|---|
| `MEMBERSHIP_ETH_PAYMENT_RPC_URL` | RPC **Sepolia**, cùng mạng đã dùng để deploy. |
| `MEMBERSHIP_ETH_PAYMENT_CONTRACT_ADDRESS` | Địa chỉ **contract EthPayment** từ dòng `Deployed to`. Đây không phải địa chỉ ví nhận tiền; backend dùng nó để kiểm tra giao dịch và event. |
| `MEMBERSHIP_ETH_PAYMENT_QUOTE_SIGNER_PRIVATE_KEY` | **Private key của ví HomeSpace** tương ứng `$ownerAddress`. Backend ký báo giá bằng key này; địa chỉ suy ra phải khớp `quoteSigner()` trên contract. |
| `MEMBERSHIP_ETH_PAYMENT_RECIPIENT_ADDRESS` | **Địa chỉ công khai của cùng ví HomeSpace** (`$ownerAddress`). Khi **chủ nhà mua gói hội viên** bằng MetaMask của họ, contract chuyển Sepolia ETH đến địa chỉ này. |

Các tên cũ `RENTAL_ETH_PAYMENT_*` không dùng trong luồng hội viên. Ví chủ nhà là **ví trả tiền**; contract là nơi kiểm tra chữ ký và chuyển tiền; ví HomeSpace ở `RECIPIENT_ADDRESS` là **ví nhận tiền**. Không điền địa chỉ contract vào `RECIPIENT_ADDRESS`.

Khởi động lại backend sau khi sửa `.env`. Nếu thiếu một trong các cấu hình này, API báo giá ETH trả lỗi cấu hình và không gửi giao dịch.

Backend lưu challenge và báo giá trong bảng mới. Môi trường dev với `JPA_DDL_AUTO=update` sẽ tạo bảng khi khởi động; môi trường dùng `validate` cần cấp schema trước. Không đổi chế độ schema của production chỉ để thử tính năng.

## 7. Thử thanh toán

Đăng nhập bằng tài khoản chủ nhà, chọn gói hội viên trả phí và phương thức ETH Sepolia bên cạnh SePay. Kết nối MetaMask vào Sepolia (chain ID `11155111`), lấy báo giá và kiểm tra ví nhận là ví nền tảng của bạn, số wei, thời hạn. Chỉ xác nhận trên MetaMask khi các thông tin khớp. Backend đối chiếu transaction/event và yêu cầu 3 block xác nhận trước khi kích hoạt gói.

Với nâng cấp được giảm phần chênh lệch trong 24 giờ đầu, báo giá ETH hết hạn trước mốc 24 giờ. Backend xét thời điểm giao dịch được ghi vào block đã xác minh, nên việc chờ đủ 3 block sau mốc đó không làm mất ưu đãi nếu giao dịch đã vào block kịp thời.

Trước khi thanh toán, lấy `paymentId` từ báo giá backend và kiểm tra chưa dùng (kết quả `false`):

```powershell
$paymentId = '0xPAYMENT_ID_64_KY_TU_HEX_TU_BAO_GIA'
if ($paymentId -notmatch '^0x[0-9a-fA-F]{64}$') { throw 'Chưa điền paymentId từ báo giá.' }
cast call $ethPaymentAddress 'paidPayments(bytes32)(bool)' $paymentId --rpc-url $rpcUrl
```

Sau khi MetaMask báo giao dịch thành công, đọc receipt bằng `cast receipt 0xTX_HASH --rpc-url $rpcUrl`: `status` phải thành công, `to` phải là `$ethPaymentAddress`, log `PaymentReceived` phải khớp `paymentId`, ví trả, ví nhận và số wei trong báo giá. Gọi lại `paidPayments(bytes32)` với cùng ID phải trả `true`. Sau ít nhất 3 block xác nhận, gửi hash giao dịch cho HomeSpace để đối soát; đơn hội viên mới chuyển sang `PAID` và kích hoạt gói. Không gửi lại cùng `paymentId`: contract sẽ từ chối. Nếu chưa thấy trạng thái xác nhận, kiểm tra RPC, receipt và log trước khi thử tiếp; không tự đánh dấu đã thanh toán.

Giá **ETH Mainnet/VND** từ CoinGecko chỉ dùng để tính lượng wei thử nghiệm; Sepolia ETH không có giá trị thị trường tương ứng. Phí gas do ví trả riêng. Không dùng khoản tiền hoặc ví Mainnet trong luồng này.

Tài liệu Foundry: [Deploy và verify bằng Forge](https://getfoundry.sh/forge/), [keystore](https://getfoundry.sh/cast/).

---

## ABI và chữ ký EIP-712

Phạm vi: chủ nhà mua hoặc nâng cấp gói hội viên (không xử lý hóa đơn thuê tháng).  
Contract: `src/EthPayment.sol`  
Target chain: Sepolia `chainId = 11155111`.

### EIP-712 domain

| Field | Value |
|---|---|
| name | `HomeSpaceEthPayment` |
| version | `1` |
| chainId | deployment chain (`11155111` on Sepolia) |
| verifyingContract | deployed `EthPayment` address |

Domain type: `EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)`.

### Typed data

Primary type (field order exact):

```text
PaymentQuote(bytes32 paymentId,address payer,address recipient,uint256 amountWei,uint256 expiresAt)
```

Typehash:

```text
keccak256("PaymentQuote(bytes32 paymentId,address payer,address recipient,uint256 amountWei,uint256 expiresAt)")
```

Digest signed by `quoteSigner` (65-byte `r || s || v`, same as `eth_signTypedData_v4` / Foundry `vm.sign`):

```text
structHash = keccak256(abi.encode(PAYMENT_QUOTE_TYPEHASH, paymentId, payer, recipient, amountWei, expiresAt))
digest     = keccak256("\x19\x01" || domainSeparator || structHash)
```

Helper on-chain: `hashPaymentQuote(paymentId, payer, recipient, amountWei, expiresAt)`.

### Call ABI

```text
pay(bytes32 paymentId, address payer, address recipient, uint256 amountWei, uint256 expiresAt, bytes signature) payable
```

Requirements enforced on-chain:

- `msg.sender == payer`
- `msg.value == amountWei` (exact wei)
- `block.timestamp <= expiresAt`
- ECDSA recovery of signature equals `quoteSigner`
- `paymentId` not previously paid (`paidPayments[paymentId]`)
- ETH forwarded to `recipient` via `call`; contract retains no balance on success

Also available: `quoteSigner()`, `paidPayments(bytes32)`, `setQuoteSigner(address)` (owner), Ownable2Step ownership helpers.

### Event for receipt verification

```text
PaymentReceived(bytes32 indexed paymentId, address indexed payer, address indexed recipient, uint256 amountWei)
```

Indexed order: `paymentId`, `payer`, `recipient`; `amountWei` in data.

### Tests

```text
forge test --match-contract EthPaymentTest -vv
# includes failed-recipient-transfer: pay reverts EthTransferFailed and paidPayments[paymentId] stays false
```
