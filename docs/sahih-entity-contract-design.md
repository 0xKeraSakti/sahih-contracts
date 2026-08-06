# Sahih — Entity & Contract Design

## Entity

**1. Investor**
Pemodal yang beli fraksi token sukuk, mulai Rp100rb. Direpresentasikan sebagai wallet address plus profil KYC-lite di BE (nama, kontak). Di on-chain, investor cuma dikenali lewat address-nya sebagai holder token.

**2. Issuer (UMKM/badan usaha)**
Pihak yang menerbitkan sukuk. Punya profil lengkap di BE (legalitas, koneksi QRIS), dan direpresentasikan di on-chain lewat kontrak token yang dideploy khusus untuknya via factory.

**3. Agent (AI)**
Sistem otomatis di backend yang menjalankan 3 fungsi: verifikasi omzet, kalkulasi bagi hasil, skoring risiko. Tidak punya wallet address sendiri secara konsep bisnis, tapi butuh eksekutor untuk menulis hasil kerjanya ke chain.

**4. Platform Operator**
Wallet address on-chain yang dipegang backend, dipakai Agent untuk mengeksekusi transaksi seperti `createIssuerToken`, `attestVerification`, dan `recordDistribution`. Agent adalah otak yang mikir dan hitung, Platform Operator adalah tangan yang menulis hasil ke blockchain. Hanya address Operator ini yang punya permission memanggil fungsi-fungsi sensitif.

Investor dan Issuer adalah entity bisnis dengan kepentingan ekonomi langsung. Agent dan Platform Operator adalah bagian infrastruktur sistem yang menjalankan proses secara otomatis dan terpercaya.

### Delegasi Agent → Platform Operator

Pattern yang dipakai: **Agent-triggered signing**, bukan human-in-the-loop.

- Agent (logic kalkulasi di backend) menghasilkan payload
- Payload langsung dikirim ke fungsi signing yang menggunakan private key Platform Operator (disimpan di secrets manager, TIDAK hardcoded, TIDAK di environment variable plaintext)
- Tidak ada approval manual antara kalkulasi dan eksekusi untuk MVP scope ini
- Setiap signing WAJIB dicatat di log terpisah (agent execution log) yang bisa diaudit kapan pun

Ini bukan multi-sig, bukan threshold approval. Untuk versi production nanti (di luar scope MVP ini), pattern yang lebih defensif seperti ambang batas nominal atau approval kedua bisa ditambahkan, tapi TIDAK untuk implementasi saat ini.

### Access Control Pattern

Semua kontrak yang punya fungsi sensitif (createIssuerToken, recordDistribution, attest*) HARUS pakai modifier yang membatasi caller hanya ke address Platform Operator yang terdaftar.

Gunakan pattern OpenZeppelin `Ownable` atau `AccessControl` (role-based), JANGAN bikin access control custom dari nol. Role yang dibutuhkan minimal:
- `OPERATOR_ROLE` — bisa panggil createIssuerToken, recordDistribution, attestVerification, attestScore, attestDistribution
- `ADMIN_ROLE` — bisa update/revoke OPERATOR_ROLE, untuk key rotation kalau private key Platform Operator perlu diganti

Key rotation harus dimungkinkan tanpa redeploy kontrak. Ini alasan kenapa AccessControl role-based lebih tepat dibanding Ownable sederhana — kalau suatu saat Platform Operator key perlu diganti (rotasi keamanan, migrasi service), ADMIN cukup grant role ke address baru dan revoke dari address lama.

---

## Factory Contract

### createIssuerToken (write, OPERATOR_ROLE only)
Payload:
```json
{
  "issuerId": "string",
  "tokenName": "string",
  "tokenSymbol": "string",
  "totalSupply": "number",
  "pricePerUnit": "number",
  "profitSharingRatio": "number",
  "distributionPeriod": "weekly",
  "transferRestricted": true
}
```
Response:
```json
{
  "contractAddress": "0x...",
  "issuerId": "string",
  "deployedAt": "timestamp"
}
```

### getIssuerContract (view)
Payload:
```json
{ "issuerId": "string" }
```
Response:
```json
{
  "contractAddress": "0x...",
  "deployedAt": "timestamp",
  "status": "active"
}
```

### listAllIssuers (view)
Payload:
```json
{ "page": 1, "limit": 20 }
```
Response:
```json
{
  "issuers": [{ "issuerId": "string", "contractAddress": "0x..." }],
  "totalCount": "number"
}
```

---

## Token Contract (per issuer, ERC-20 extended)

### purchaseTokens (write, public — investor calls directly)
Payload:
```json
{
  "investorAddress": "0x...",
  "amount": "number",
  "paymentSource": "string"
}
```
Response:
```json
{
  "investorAddress": "0x...",
  "newBalance": "number",
  "purchasedAt": "timestamp",
  "txHash": "0x..."
}
```

### balanceOf (view, standard ERC-20)
Payload:
```json
{ "investorAddress": "0x..." }
```
Response:
```json
{ "balance": "number" }
```

### getIssuerTerms (view)
Payload:
```json
{}
```
Response:
```json
{
  "profitSharingRatio": "number",
  "totalSupply": "number",
  "pricePerUnit": "number",
  "distributionPeriod": "weekly",
  "transferRestricted": true
}
```

### transfer (override, restricted)
Payload:
```json
{ "toAddress": "0x...", "amount": "number" }
```
Response:
```json
{ "success": false, "reason": "transfer_restricted" }
```
kecuali toAddress whitelisted.

---

## Distribution Contract

### recordDistribution (write, OPERATOR_ROLE only)
Payload:
```json
{
  "issuerContractAddress": "0x...",
  "period": "2026-W32",
  "totalAmount": "number",
  "distributions": [{ "holderAddress": "0x...", "amount": "number" }],
  "calculationRefHash": "0x..."
}
```
Response:
```json
{
  "period": "2026-W32",
  "totalAmount": "number",
  "distributedAt": "timestamp",
  "txHash": "0x...",
  "attestationRef": "0x..."
}
```

Behavior: loop distributions, transfer amount ke tiap holderAddress, emit event `Distributed(issuer, period, totalAmount, timestamp)` — breakdown detail per holder TIDAK masuk event (hemat gas), cukup total. Simpan calculationRefHash ke storage.

### getDistributionHistory (view)
Payload:
```json
{
  "issuerContractAddress": "0x...",
  "fromPeriod": "2026-W20",
  "toPeriod": "2026-W32"
}
```
Response:
```json
{
  "history": [
    { "period": "2026-W32", "totalAmount": "number", "distributedAt": "timestamp", "txHash": "0x..." }
  ]
}
```

### getInvestorDistributions (view)
Payload:
```json
{ "investorAddress": "0x..." }
```
Response:
```json
{
  "distributions": [
    { "issuerContractAddress": "0x...", "period": "2026-W32", "amount": "number", "distributedAt": "timestamp" }
  ]
}
```

---

## EAS Attestation

### attestVerification (write, OPERATOR_ROLE only)
Payload:
```json
{
  "issuerId": "string",
  "period": "2026-W32",
  "avgRevenue": "number",
  "volatilityIndex": "number",
  "dataRefHash": "0x...",
  "timestamp": "timestamp"
}
```
Response:
```json
{ "attestationUID": "0x..." }
```

### attestScore (write, OPERATOR_ROLE only)
Payload:
```json
{
  "issuerId": "string",
  "score": "number",
  "scoringMethodVersion": "string",
  "period": "2026-W32",
  "timestamp": "timestamp"
}
```
Response:
```json
{ "attestationUID": "0x..." }
```

### attestDistribution (write, OPERATOR_ROLE only)
Payload:
```json
{
  "issuerId": "string",
  "period": "2026-W32",
  "totalAmount": "number",
  "calculationRefHash": "0x...",
  "timestamp": "timestamp"
}
```
Response:
```json
{ "attestationUID": "0x..." }
```

Catatan: avgRevenue HANYA muncul di attestVerification, TIDAK di attestDistribution. attestDistribution merujuk balik ke periode yang sama lewat issuerId + period, bukan mengulang angka omzet.

### getAttestation (view)
Payload:
```json
{ "attestationUID": "0x..." }
```
Response:
```json
{
  "issuerId": "string",
  "period": "2026-W32",
  "value": "number | string",
  "dataRefHash": "0x...",
  "timestamp": "timestamp",
  "attesterAddress": "0x..."
}
```

---

## Catatan Desain Penting

- Setiap attestation adalah entry BARU per periode, TIDAK ada update pada attestation lama. Riwayat terbentuk dari akumulasi attestation, bukan dari mutasi record.
- Enumerasi holder TIDAK dilakukan on-chain (mahal gas). Holder list & balance diindeks dari event `Purchase` oleh backend indexer.
- Tidak ada kalkulasi bagi hasil di dalam Solidity. Semua kalkulasi (omzet × ratio × proporsi balance) terjadi di backend, kontrak hanya mengeksekusi hasil yang sudah dihitung.
- Tidak ada retry/rollback logic kompleks di kontrak. Kegagalan transfer parsial ditangani di level backend dengan re-trigger recordDistribution memakai array yang sudah dikoreksi.
