# Bản đồ tài liệu — Dự án AES-256 & SHA-256 IP

**Đề tài:** Thiết kế và tích hợp IP mã hóa AES-256 và SHA-256 cho giao thức truyền và nhận dữ liệu
**Đội:** Hủ Tiếu — Trường ĐH Công nghệ Thông tin và Truyền thông, ĐH Thái Nguyên
**Nhánh:** `feat/aes-sha256-ip-integration`
**Bắt đầu:** 2026-09-09

---

## 1. Tài liệu này để làm gì

Repository này không tách rời "code" và "giấy tờ". Tài liệu ở đây là **một phần của hệ
thống kỹ thuật**, giữ ba vai trò:

1. **Bộ nhớ dự án** — giữ lại business intent và lý do thiết kế mà source code không tự
   nói ra được.
2. **Giao diện điều khiển** — cung cấp context, ràng buộc, definition of done và ranh giới
   tự chủ cho người (và AI) làm việc trên repo.
3. **Hạ tầng review** — cho phép người chấm đi từ yêu cầu → thiết kế → code → test mà
   không phải suy luận lại toàn bộ hệ thống từ Verilog.

Nguồn sự thật *có thể thực thi* vẫn là source code trong `rtl/`. Tài liệu là bản đồ chạy
song song với lãnh thổ đó.

## 2. Artifact chain

Thứ tự các bước, và artifact tương ứng. Mỗi bước chỉ được coi là xong khi qua gate của nó
(xem `06-gates/`).

| # | Bước | Artifact | Trạng thái |
|---|------|----------|-----------|
| 1 | Làm rõ scope | [`00-scope/SCOPE.md`](00-scope/SCOPE.md) | ✅ |
| 2 | Viết spec | [`01-spec/SRS.md`](01-spec/SRS.md) | ✅ |
| 3 | Module map | [`02-module-map/MODULE_MAP.md`](02-module-map/MODULE_MAP.md) | ✅ |
| 4 | Architecture | [`03-architecture/ARCHITECTURE.md`](03-architecture/ARCHITECTURE.md) | ✅ |
| 4b | Hợp đồng interface IP | [`03-architecture/IP_INTERFACE_CONTRACT.md`](03-architecture/IP_INTERFACE_CONTRACT.md) | ✅ |
| 5 | WBS | [`04-plan/WBS.md`](04-plan/WBS.md) | ✅ |
| 6 | Estimation | [`04-plan/ESTIMATION.md`](04-plan/ESTIMATION.md) | ✅ |
| 7 | Risk & delegation | [`05-risk/RISK_DELEGATION.md`](05-risk/RISK_DELEGATION.md) | ✅ |
| 8 | Definition of Ready / Done | [`06-gates/`](06-gates/) | ✅ |
| 9 | Vertical slice | `rtl/` + [`10-devbook/DEVELOPMENT_BOOK.md`](10-devbook/DEVELOPMENT_BOOK.md) | 🚧 |
| 10 | Test & gate | [`07-test/TEST_PLAN.md`](07-test/TEST_PLAN.md) | 🚧 |
| 11 | Traceability & telemetry | [`08-traceability/RTM.md`](08-traceability/RTM.md) | 🚧 |

Xuyên suốt: [`09-decisions/`](09-decisions/) (ADR — mỗi quyết định kiến trúc một file) và
[`10-devbook/DEVELOPMENT_BOOK.md`](10-devbook/DEVELOPMENT_BOOK.md) (nhật ký: đã thử gì, sai
ở đâu, vì sao chọn hướng hiện tại).

## 3. Quy tắc bắt buộc — cập nhật ngược

> **Một thay đổi code không kèm cập nhật tài liệu liên quan trong CÙNG commit là một
> thay đổi chưa hoàn thành.**

Cụ thể, khi chạm vào `rtl/`:

| Nếu bạn thay đổi… | Bắt buộc cập nhật |
|---|---|
| Cổng (port) của một module | `02-module-map/MODULE_MAP.md` |
| Giao thức bắt tay giữa IP và wrapper | `03-architecture/IP_INTERFACE_CONTRACT.md` |
| Định dạng khung truyền | `01-spec/SRS.md` §4 và `07-test/TEST_PLAN.md` |
| Một quyết định đánh đổi (tài nguyên, throughput, thuật toán) | ADR mới trong `09-decisions/` |
| Bất kỳ hành vi nào có requirement ID | `08-traceability/RTM.md` |
| Con số tài nguyên / F_max | `10-devbook/DEVELOPMENT_BOOK.md` §Số đo |

## 4. Quy ước mã định danh

| Tiền tố | Nghĩa | Ví dụ |
|---|---|---|
| `REQ-F-nn` | Yêu cầu chức năng | `REQ-F-03` |
| `REQ-P-nn` | Yêu cầu hiệu năng | `REQ-P-01` |
| `REQ-I-nn` | Yêu cầu giao diện | `REQ-I-02` |
| `REQ-C-nn` | Ràng buộc | `REQ-C-01` |
| `MOD-xxx` | Module RTL | `MOD-AES-CORE` |
| `TC-nnn` | Test case | `TC-014` |
| `ADR-nnn` | Architecture Decision Record | `ADR-002` |
| `RSK-nn` | Rủi ro | `RSK-04` |
| `WP-nn` | Work package (WBS) | `WP-03` |

## 5. AI được phép làm đến đâu

Xem `05-risk/RISK_DELEGATION.md` §3. Tóm tắt: AI được tự chủ ở vùng có testbench chặn
(RTL đơn vị, testbench, script build). AI **phải dừng để người quyết định** ở: thay đổi
định dạng khung, thay đổi thuật toán mật mã, thay đổi ràng buộc chân/điện áp, và bất kỳ
kết luận nào về "đã chạy được trên phần cứng" mà chưa có log thật.

Nguyên tắc: **AI-generated ≠ done.** Một artifact chỉ hoàn thành khi người phụ trách giải
thích được nó, chỉ ra được ít nhất một chỗ AI sai/thiếu, sửa lại, và chứng minh gate liên
quan đã qua. Các lần sửa đó được ghi vào `10-devbook/DEVELOPMENT_BOOK.md` §Human correction
log.

## 6. Thư mục `_legacy/`

`docs/_legacy/` chứa tài liệu của bản thiết kế trước (repo gốc `cast-256`). Giữ lại làm
đối chiếu, **không** phải nguồn sự thật cho đề tài này.
