# infra

여러 프로젝트가 함께 쓰는 개인 인프라. Terraform 으로 OCI 에 VM 을 만들고, 그 위에서 docker compose 로 서비스를 돌린다.

## 현재 상태 (2026-09-25 기준)

| 항목 | 값 |
|---|---|
| 클라우드 / 리전 | OCI, `ap-chuncheon-1` (춘천, 가용 도메인 1개) |
| VM | `VM.Standard.E2.1.Micro` (x86, 1 OCPU, 1GB, Always Free), Ubuntu 22.04, 이름 `infra-vm` |
| 도메인 | `lumia.ncookie.site` (가비아 DNS 의 A 레코드 → VM 공인 IP), caddy 가 Let's Encrypt 로 HTTPS 자동 발급 |
| 서비스 | receiver (lumia_briefing_room 라벨·로그 수신 API), caddy, watchtower |
| 이미지 | `ghcr.io/ncookies/receiver:latest` (public 패키지) |
| Terraform 상태 | 로컬 `terraform/terraform.tfstate` (git 제외) |

확인: `https://lumia.ncookie.site/healthz` → `{"status":"ok"}`

```
terraform/            OCI: VCN·인터넷 게이트웨이·라우트 테이블·보안 목록·서브넷·VM (cloud-init 이 도커와 compose 를 올림)
deploy/               서버에서 도는 docker-compose.yml (caddy + receiver + watchtower), Caddyfile
services/receiver/    lumia_briefing_room 라벨·로그 수신 API (FastAPI, 1단계 저장: 파일)
.github/workflows/    receiver 테스트 → ghcr.io 이미지 빌드(amd64+arm64)
```

## 최초 구성 (처음부터 다시 만들 때)

준비물: OCI 계정, GitHub 계정, 도메인(DNS 를 수정할 수 있는 곳), Terraform·Git·ssh 클라이언트가 깔린 PC.

### 1. OCI API 키와 `~/.oci/config`

Terraform 이 OCI 에 로그인하는 데 쓰는 키다. SSH 키(2단계)와 **별개**다.

1. OCI 콘솔 우측 상단 프로필 → **My profile** → **API keys** → **Add API key** → **Generate API key pair**.
2. **개인키(.pem)를 다운로드**한다. 공개키는 OCI 가 자동 등록한다.
3. **Add** 를 누르면 나오는 "Configuration file preview" 를 통째로 복사한다.
4. `C:\Users\<사용자>\.oci\config` 에 저장한다.
   - **파일 이름은 확장자 없이 `config`**. 메모장에서 `config.txt` 가 되지 않게 저장 형식을 "모든 파일" 로 둔다.
   - **폴더 위치를 조심한다.** 반드시 사용자 폴더 안(`C:\Users\<사용자>\.oci`)이어야 한다. 실수로 `C:\Users\.oci` 에 만들면 `open C:\Users\<사용자>/.oci/config: The system cannot find the path specified` 오류가 난다.
   ```powershell
   New-Item -ItemType Directory -Force $HOME\.oci
   notepad $HOME\.oci\config
   ```
5. 다운로드한 `.pem` 을 같은 폴더에 두고, config 의 **`key_file=` 을 절대 경로로** 고친다. 상대 경로(`key_file=oci_api_key.pem`)로 두면 Terraform 이 작업 폴더 기준으로 찾아서 `did not find a proper configuration for private key` 오류가 난다.
   ```
   key_file=C:\Users\<사용자>\.oci\oci_api_key.pem
   ```
6. `.pem` 첫 줄이 `-----BEGIN PRIVATE KEY-----` 인지 확인한다(`BEGIN PUBLIC KEY` 면 공개키를 받은 것).

`[DEFAULT]` 는 프로파일 이름이며 Terraform 변수 `oci_config_profile` 의 기본값과 같다. 개인키는 저장소 밖(`~/.oci`)에 두고 절대 커밋하지 않는다.

### 2. VM 접속용 SSH 키

```powershell
ssh-keygen -t ed25519 -f $HOME\.ssh\oci_infra -C "oci-infra"
Get-Content $HOME\.ssh\oci_infra.pub
```

- 개인키(`oci_infra`)는 공유하지 않는다. `.pub`(공개키) 한 줄 전체를 `ssh_public_key` 에 넣는다.
- 접속: `ssh -i $HOME\.ssh\oci_infra ubuntu@<public_ip>`

### 3. `terraform/terraform.tfvars`

`terraform.tfvars.example` 을 복사해 채운다. 이 파일은 `.gitignore` 로 커밋되지 않는다(토큰이 들어 있다).

| 변수 | 값을 구하는 곳 |
|---|---|
| `region` | 콘솔 우측 상단 리전. 형식 `ap-chuncheon-1`. `~/.oci/config` 의 `region=` 과 같아야 한다. 무료 계정은 **홈 리전**에서만 Always Free 자원을 쓴다 |
| `oci_config_profile` | config 의 `[DEFAULT]` 이름 |
| `compartment_ocid` | 프로필 메뉴 → **Tenancy** 의 OCID (`ocid1.tenancy.oc1..…`). **`ocid1.user…` 는 사용자 OCID 라 틀린 값이다.** 별도 컴파트먼트를 만들었다면 그 OCID |
| `ssh_public_key` | 2단계의 `.pub` 한 줄 |
| `ssh_allowed_cidr` | SSH(22) 를 허용할 IP. `curl https://api.ipify.org` 로 내 공인 IP 를 확인해 `1.2.3.4/32` 형태로 넣는다 |
| `instance_shape` | 현재 `"VM.Standard.E2.1.Micro"` (아래 "VM shape" 참고) |
| `site_address` | 서비스 도메인(`lumia.ncookie.site`). 비우면 `:80` 평문 HTTP |
| `receiver_image` | `ghcr.io/<GitHub 소유자 소문자>/receiver:latest` |
| `receiver_api_token` | 직접 만든 긴 랜덤 문자열. `python -c "import secrets; print(secrets.token_urlsafe(32))"`. 앱의 전송 클라이언트도 같은 값을 `X-Api-Token` 으로 보낸다 |

### 4. GitHub 저장소와 이미지

1. `https://github.com/NCookies/infra` 에 push (기본 브랜치 `main`, 워크플로가 `main` 에서만 돈다).
2. **Actions** 탭에서 `receiver` 워크플로가 성공하는지 본다. ghcr 은 **저장소 이름이 소문자**여야 해서 워크플로가 소유자 이름을 소문자로 바꿔 태그한다(`NCookies` → `ncookies`). 이걸 안 하면 `repository name must be lowercase` 로 실패한다.
3. 프로필 → **Packages** → `receiver` → **Package settings** → 공개 범위를 **Public** 으로 바꾼다. 비공개면 서버의 watchtower 가 인증 없이 pull 할 수 없다(대안: 서버에서 `docker login ghcr.io`).
   - 확인: 익명으로 `https://ghcr.io/v2/ncookies/receiver/manifests/latest` 를 조회했을 때 200.

### 5. Terraform 실행

```powershell
cd terraform
terraform init
terraform plan      # 6개 리소스 생성 예정인지 확인. 인증·이미지 조회까지 검증하지만 VM 생성 가능 여부는 알 수 없다
terraform apply     # yes 입력
```

끝나면 `public_ip` 가 출력된다(`terraform output` 으로 다시 볼 수 있다).

### 6. DNS

가비아 → DNS 관리에서 **A 레코드**를 추가한다.

- 호스트: `lumia` (전체 도메인이 아니라 앞부분만), 값: `<public_ip>`
- **IP 는 A 레코드, 도메인 이름을 가리킬 때만 CNAME.** Vercel 처럼 서비스가 도메인 이름을 주는 경우는 CNAME 이고, OCI 는 IP 를 주므로 A 다. 같은 호스트에 A 와 CNAME 을 함께 둘 수 없다.
- DNS 가 전파되면 caddy 가 스스로 재시도해서 인증서를 받는다(몇 분).

### 7. 확인

cloud-init(패키지 갱신·도커 설치·이미지 pull)이 1GB micro 에서는 5~10분 걸린다. 그 전에는 `/healthz` 가 연결되지 않는다(SSH 만 먼저 열린다).

```powershell
curl https://lumia.ncookie.site/healthz            # {"status":"ok"}
```

토큰 인증도 확인한다: 토큰 없이 `POST /v1/labels` → 401, 토큰과 함께 → `{"saved":N}`.

## VM shape 과 무료 한도

- 원래 계획은 `VM.Standard.A1.Flex`(ARM, 1 OCPU, 6GB)였으나 `terraform apply` 의 `LaunchInstance` 가 `404-NotAuthorizedOrNotFound` 로 실패했다. 네트워크는 같은 컴파트먼트에 만들어졌으므로 권한 문제가 아니고, 그 shape 을 이 계정·가용 도메인에서 쓸 수 없는 경우로 보이나 **원인은 확인하지 못했다.**
- 콘솔(Compute → Instances → Create instance)의 shape 화면에서 기본 선택이 `VM.Standard.E2.1.Micro`(Always Free-eligible)였고, 그래서 이걸로 전환했다. Free tier 는 E2.1.Micro 를 **계정당 2개**까지 쓴다.
- 콘솔의 "Service limits status: Some resource limit is critical" 경고는 오류가 아니라 사용량 경고다. `Cores for StandardE2 based VM and BM micro instances: 1 of 2` — 이전에 다른 프로젝트에서 만들다 만 micro 가 1개 있어서 한도의 절반이 이미 쓰이고 있었다. 이 VM 이 두 번째라 **지금은 micro 슬롯이 남아 있지 않다.** 옛 인스턴스가 필요 없으면 콘솔에서 직접 정리한다(중지 상태도 슬롯과 부트 볼륨 무료 한도를 쓴다).
- E2.1.Micro 는 Flex shape 이 아니라 `instance_ocpus`·`instance_memory_gbs` 를 무시한다. 메모리 1GB 라 여유가 없다 — 서비스가 늘면 스왑을 추가하거나 A1 을 다시 시도한다.
- A1 을 다시 시도할 때는 `instance_shape = "VM.Standard.A1.Flex"` 로 바꿔 apply. 리전에 따라 `Out of host capacity` 도 날 수 있다.

## 운영

### 서버 접속과 상태 확인

```powershell
ssh -i $HOME\.ssh\oci_infra ubuntu@<public_ip>
```

서버 안에서:

```bash
cd /opt/infra
docker compose ps
docker compose logs -f receiver
sudo cloud-init status
sudo tail -30 /var/log/cloud-init-output.log     # 부팅 스크립트 로그 (.env 의 토큰이 찍히지 않았는지 공유 전 확인)
```

- `/opt/infra/docker-compose.yml`, `Caddyfile`, `.env` 는 cloud-init 이 만든 것이다. `.env` 는 `0600`.
- 수신 데이터는 `/opt/infra/data/{labels,logs,diagnostics}/<installId>/` (컨테이너 사용자 uid 10001 소유). 개발 모드(`mode=dev`) 데이터는 `/opt/infra/data/dev/` 아래에 따로 쌓인다. 일별 집계는 `/opt/infra/data/stats/<날짜>.json`.

### 자동 업데이트

`services/receiver/**` 를 main 에 push → Actions 가 테스트 후 이미지를 갱신 → 서버의 watchtower 가 주기적으로 감지해 receiver 컨테이너만 교체한다. 새 서비스는 compose 에 서비스를 추가하고 `com.centurylinklabs.watchtower.enable: "true"` 라벨을 붙이면 같은 방식으로 갱신된다.

갱신 확인 간격은 `.env` 의 `WATCHTOWER_POLL_INTERVAL`(초, 기본 7200 = 2시간)이다. 개발 중 빠르게 확인하고 싶을 때만 `120` 정도로 줄이고 `docker compose up -d` 한다(`terraform.tfvars` 의 `watchtower_poll_interval` 은 VM 을 새로 만들 때 `.env` 에 들어간다).

### 설정을 바꿀 때 (VM 은 다시 만들지 않는다)

`oci_core_instance` 의 `user_data`(cloud-init) 변경과 이미지 갱신은 `lifecycle.ignore_changes` 로 무시하도록 해 뒀다. 그래서 **tfvars 나 `deploy/` 를 고쳐도 이미 떠 있는 서버에는 반영되지 않는다.** 서버에서 직접 고친다.

```bash
cd /opt/infra
sudo nano .env                # 토큰·도메인·이미지 등
sudo nano docker-compose.yml  # 서비스 추가 등
docker compose up -d
```

- **API 토큰 교체(무중단)**: 서버는 `RECEIVER_API_TOKEN` 과 쉼표로 구분한 `RECEIVER_API_TOKENS` 를 **모두** 허용한다. ① `.env` 의 `RECEIVER_API_TOKENS` 에 새 토큰을 추가하고 `docker compose up -d` ② 새 토큰을 넣은 앱 버전을 배포 ③ 대부분 업데이트한 뒤 옛 토큰을 `.env` 에서 지우고 `docker compose up -d`(그 토큰을 쓰던 앱은 401 을 받고 전송만 실패한다). 유출로 즉시 막아야 하면 ③ 을 먼저 한다.
- **관리자 토큰(라벨 내보내기)**: `.env` 의 `ADMIN_TOKEN`(값은 `terraform.tfvars` 의 `admin_token`, 로컬 `tools/pull_labels.py` 가 `LUMIA_ADMIN_TOKEN` 으로 쓴다). 비우면 `GET /v1/admin/labels` 가 꺼진다(404). 바꾸려면 `.env` 와 tfvars 를 같이 고치고 `docker compose up -d`. 업로드 토큰과 별개라 앱에는 들어가지 않는다.
- **SSH 허용 IP 변경**(공인 IP 가 바뀌어 접속이 막혔을 때): `tfvars` 의 `ssh_allowed_cidr` 를 고치고 `terraform apply` — 보안 목록만 바뀐다(VM 유지). IP 를 모르면 콘솔의 VCN → 보안 목록에서 직접 수정해도 된다.
- **도메인 변경**: 서버 `.env` 의 `SITE_ADDRESS` 수정 후 `docker compose up -d`, DNS A 레코드도 변경.

### VM 을 다시 만들 때

`terraform destroy` 후 `apply` 하면 **공인 IP 가 바뀌므로** 가비아 A 레코드를 새 IP 로 고쳐야 한다(예약 IP 를 쓰면 안 바뀌지만 아직 Terraform 에 넣지 않았다). 서버의 `/opt/infra/data` 는 함께 사라지니 필요하면 먼저 백업한다:

```powershell
scp -i $HOME\.ssh\oci_infra -r ubuntu@<public_ip>:/opt/infra/data .\backup
```

### Terraform 상태 파일

로컬 `terraform/terraform.tfstate`(git 제외). 잃어버리면 이미 만든 리소스를 Terraform 이 모르게 되어 복구가 어렵다 — 백업해 두거나 나중에 OCI Object Storage 백엔드로 옮긴다. 자격 증명·상태·`*.tfvars`·`*.pem` 은 절대 커밋하지 않는다(`.gitignore` 처리됨).

## 수신 API (receiver)

모든 `/v1/*` 는 `X-Api-Token` 헤더 필요(`receiver_api_token`, 여러 개 가능 — 위 "API 토큰 교체"). 허용 목록에 없는 필드는 버린다(버려진 필드 **이름**만 일별 집계에 센다). `installId` 는 UUID, 모든 페이로드에 `schemaVersion`·`mode`(`dev`/`release`)가 필요하다. `/docs` 등 API 문서는 꺼져 있다(404).

**요청·응답 명세의 원본은 [`contract/receiver.schema.json`](contract/receiver.schema.json)** 이고, `contract/fixtures/` 의 수락·거부·버림 예시를 서버 테스트(`tests/test_contract.py`)와 앱 저장소가 같이 쓴다. 필드를 바꿀 때는 스키마·`app/schemas.py`·픽스처를 함께 고친다(어긋나면 테스트가 깨진다). 앱 저장소의 복사본은 `tools/sync_contract.py` 로 갱신한다.

| 메서드 | 경로 | 설명 |
|---|---|---|
| GET | `/healthz` | 상태 확인(토큰 불필요) |
| POST | `/v1/labels` | 라벨 묶음 → `data/labels/<installId>/<clipKey>.json` (같은 `clipKey` 를 다시 보내면 덮어씀) → `{saved}` |
| POST | `/v1/logs` | 오류 로그·환경 → `data/logs/<installId>/<날짜>.jsonl` → `{saved}` |
| POST | `/v1/diagnostics` | 진단 번들(사용자가 버튼으로 보냄) → `data/diagnostics/<installId>/<접수번호>.json` → `{receiptId:"R-20260925-K7M3QX", saved}` |
| GET | `/v1/admin/labels` | **관리자 전용** 라벨 내보내기(`X-Admin-Token`, 업로드 토큰으로는 안 됨). `mode`(dev/release)·`after`(이전 응답의 `next`)·`limit`(최대 2000). `ADMIN_TOKEN` 이 비어 있으면 404. 앱 저장소 `tools/pull_labels.py` 가 쓴다. 로그·진단은 내보내지 않는다 |
| DELETE | `/v1/installs/{installId}` | 그 설치가 보낸 라벨·로그·진단(개발 모드 포함) 전부 삭제 |

**보관과 삭제**: 로그·진단 파일은 수신 후 `RETENTION_DAYS`(기본 90)일이 지나면 서버가 하루 한 번(그리고 시작할 때) 자동 삭제한다. 라벨은 삭제 요청 전까지 보관한다. 앱 저장소(`P:\lumia_briefing_room`)의 `docs/privacy.md` 에 적은 보관 기간과 이 값이 같아야 한다.

**IP 를 남기지 않는 설정**: caddy 는 **전역** `log { exclude http.log.access }` 로 접근 로그를 어디에도 남기지 않고(사이트 블록의 `log { output discard }` 만으로는 서버 IP 로 직접 접속한 요청이 로그에 남는다 — 2026-09-25 발견·수정), receiver 는 uvicorn `--no-access-log` 로 실행한다. 확인 방법: 서버 IP 로 `curl http://<공인 IP>/` 를 보낸 뒤 `docker compose logs caddy | grep -c http.log.access` 가 0 인지 본다. 컨테이너 로그는 크기 회전(5MB×2)만 하며, 오류 로그에 IP 가 찍히는지는 배포 후 `docker compose logs` 로 확인한다.

**요청 제한·차단·알림**: `/v1/*` 요청을 클라이언트 IP(caddy 가 붙인 `X-Forwarded-For` 의 마지막 값) 별로 세어, 10분 창에서 요청이 `RATE_LIMIT_REQUESTS`(기본 60)회를 넘거나 거부되는 요청(401·404·405·413·422)이 `RATE_LIMIT_FAILURES`(기본 15)회 쌓이면 그 IP 를 `BLOCK_SEC`(기본 3600)초 동안 차단한다(429 + `Retry-After`). `/healthz` 는 제외. 정상 앱은 하루 1회 소량만 보내므로 임계값은 넉넉하다. **IP 는 receiver 프로세스 메모리에만 있고 디스크에 쓰지 않으며 재시작하면 사라진다.** 차단이 생기면 `DISCORD_WEBHOOK_URL` 로 알린다(IP 는 앞 두 자리만, 시간당 최대 10건). 웹훅 URL 은 비밀 값이라 서버 `.env` 와 로컬 `terraform.tfvars`(`discord_webhook_url`)에만 두고 저장소에 넣지 않는다. 비워 두면 알림 없이 차단만 한다. 한계: IP 기준이라 VPN 으로 우회할 수 있고, 같은 공유기 뒤 사용자는 한 IP 로 보인다.

**일별 집계**(`data/stats/<날짜>.json`): 엔드포인트별 수신 건수·총/평균 바이트, 거부(422)된 요청 수와 거부 사유가 된 필드 이름, 허용 목록 밖이라 버린 필드 이름. 값(라벨 메모 포함)은 남기지 않는다. 앱과 서버 스키마가 어긋났는지, DB 가 필요한 규모인지 보는 자료다.

요청 본문 상한 20MB(`MAX_BODY_BYTES`, Caddy 는 21MB). 라벨 필드는 2026-09-25 에 앱의 실제 메타데이터(`ClipMetadata`)와 하나씩 대조해 확정했다(전송·제외 분류는 `contract/app-metadata-fields.json`).

로컬 개발/테스트:

```
cd services/receiver
python -m venv .venv && .venv/Scripts/python -m pip install -r requirements-dev.txt
.venv/Scripts/python -m pytest
```

2026-09-25 (계약 변경 전) 실서버 확인: 토큰 없음 → 401, 라벨 업로드(허용 밖 `nickname` 포함) → `{"saved":1}` 이며 허용 밖 필드는 버려짐, `installId` 삭제 → `{"deleted":true}`, `/docs` → 404.

2026-09-25 계약 확장 배포 후 실서버 확인(읽기 전용, 데이터를 쓰는 요청은 하지 않음): 토큰 없는 `POST /v1/diagnostics`·`/v1/labels`·`DELETE /v1/installs/…` → 401, `/docs` → 404, `/healthz` → 200. 배포 방법: main push → Actions 가 이미지 갱신, 설정 파일은 서버의 `/opt/infra` 에 직접 반영(`scp` 로 `docker-compose.yml`·`Caddyfile` 올리고 `caddy validate` 로 문법 확인 → 옛 파일은 `*.bak` 으로 백업 → `.env` 에 새 변수 추가 → `docker compose pull receiver && docker compose up -d`). `.env` 는 root 소유 0600 이라 서버에서 읽거나 고칠 때 `sudo` 가 필요하다.

## 문제 해결

| 증상 | 원인 / 해결 |
|---|---|
| `open …/.oci/config: The system cannot find the path specified` | config 가 없거나 `C:\Users\<사용자>\.oci` 가 아닌 곳에 있음 |
| `did not find a proper configuration for private key` | config 의 `key_file=` 이 상대 경로이거나 틀림 → 절대 경로로 |
| `LaunchInstance` `404-NotAuthorizedOrNotFound` (네트워크는 성공) | shape 을 쓸 수 없음. `instance_shape` 을 `VM.Standard.E2.1.Micro` 로 |
| `Out of host capacity` | A1 용량 부족. 재시도하거나 E2.1.Micro |
| `repository name must be lowercase` (Actions) | ghcr 태그에 대문자. 워크플로가 소문자로 변환하도록 고쳐 둠 |
| `compartment_ocid` 가 `ocid1.user…` | 사용자 OCID 임. Tenancy OCID 로 교체 |
| IP 로 `/healthz` 접속 시 308 | 도메인을 지정한 caddy 의 HTTPS 리다이렉트. 정상. `https://<도메인>` 으로 접속 |
| 서버 SSH 는 되는데 80/443 이 안 됨 | cloud-init 진행 중(5~10분). `sudo cloud-init status` |
| HTTPS 인증서가 안 나옴 | DNS A 레코드가 VM IP 를 가리키는지, 80/443 이 열려 있는지 확인. `docker compose logs caddy` |
| SSH 접속 거부 | 공인 IP 가 바뀜. `ssh_allowed_cidr` 갱신 |

## 나중에 AWS 등을 추가한다면

`deploy/` 와 `services/` 는 클라우드와 무관하므로 그대로 재사용할 수 있다. Terraform 은 상태 파일·apply 를 분리하려고 `terraform/` 을 `terraform/oci/`, `terraform/aws/` 로 나눈다(로컬 상태 파일도 같이 옮긴다).

## 알려진 한계

- 앱에 토큰이 들어가므로 완전한 인증이 아니다(공개 키 수준). 실질 방어는 필드 허용 목록·크기 상한·IP 별 요청 제한이다.
- 청크 전송은 Content-Length 검사를 우회하지만 본문을 읽은 뒤 크기를 다시 검사하고(413), Caddy 의 `request_body max_size` 도 상한을 강제한다.
- 공인 IP 가 예약 IP 가 아니라서 VM 을 다시 만들면 바뀐다.
- 저장은 파일뿐이다(2단계 DB 는 아직).
- 1GB 메모리 VM 이라 서비스를 늘리면 부족할 수 있다.
