# infra

여러 프로젝트가 함께 쓰는 OCI 인프라. Terraform 으로 VM 을 만들고, 그 위에서 docker compose 로 서비스를 돌린다.

```
terraform/            OCI: VCN·서브넷·보안목록·Ubuntu VM (cloud-init 이 도커와 compose 를 올림)
deploy/               서버에서 도는 docker-compose.yml (caddy + 서비스들 + watchtower), Caddyfile
services/receiver/    lumia_briefing_room 라벨·로그 수신 API (FastAPI, 1단계 저장: 파일)
.github/workflows/    receiver 테스트 → ghcr.io 이미지 빌드(amd64+arm64)
```

## 최초 구성

1. OCI API 키 준비 → `~/.oci/config` (프로파일 이름은 `oci_config_profile`).
2. `terraform/terraform.tfvars.example` 을 `terraform.tfvars` 로 복사해 채운다(커밋 금지, `.gitignore` 처리됨).
3. GitHub 에 push → Actions 가 `ghcr.io/<user>/receiver:latest` 를 만든다. 패키지를 **public** 으로 바꾸거나(watchtower 가 인증 없이 pull), 서버에서 `docker login ghcr.io` 를 한다.
4. ```
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```
5. `terraform output` 의 `receiver_health_url` 로 확인. cloud-init 이 도는 데 몇 분 걸린다.

상태 파일은 로컬(`terraform.tfstate`, git 제외). 잃어버리면 복구가 어려우니 백업하거나 나중에 OCI Object Storage 백엔드로 옮긴다.

## 자동 업데이트

`services/receiver/**` 를 main 에 push → Actions 가 이미지를 갱신 → 서버의 watchtower 가 5분 간격으로 감지해 receiver 컨테이너만 교체한다. 새 서비스는 compose 에 서비스를 추가하고 `com.centurylinklabs.watchtower.enable: "true"` 라벨을 붙이면 같은 방식으로 갱신된다.

`deploy/` 나 환경변수를 바꿀 때는 VM 을 다시 만들지 않는다(`user_data` 변경은 무시하도록 설정함). 서버에서 `/opt/infra` 의 파일을 고치고 `docker compose up -d` 한다.

## 수신 API (receiver)

모든 `/v1/*` 는 `X-Api-Token` 헤더 필요(`receiver_api_token`). 허용 목록에 없는 필드는 버린다. `installId` 는 UUID 여야 한다.

| 메서드 | 경로 | 설명 |
|---|---|---|
| GET | `/healthz` | 상태 확인(토큰 불필요) |
| POST | `/v1/labels` | `{installId, appVersion, labels:[...]}` → `data/labels/<installId>/<id>.json` |
| POST | `/v1/logs` | `{installId, env, entries:[{ts,level,message}]}` → `data/logs/<installId>/<날짜>.jsonl` |
| DELETE | `/v1/installs/{installId}` | 그 설치가 보낸 데이터 전부 삭제 |

요청 본문 상한 20MB(`MAX_BODY_BYTES`, Caddy 는 21MB). 데이터는 VM 의 `/opt/infra/data`.

로컬 개발/테스트:

```
cd services/receiver
python -m venv .venv && .venv/Scripts/python -m pip install -r requirements-dev.txt
.venv/Scripts/python -m pytest
```

## 알려진 한계

- 도커 이미지 빌드·compose 실행과 `terraform apply` 는 실제로 실행해 보지 않았다(`terraform validate` 와 receiver 테스트만 확인).
- 요청 빈도 제한이 없다(크기 상한과 공유 토큰만). 앱에 토큰이 들어가므로 완전한 인증이 아니다.
- 청크 전송은 Content-Length 검사를 우회한다. Caddy 의 `request_body max_size` 가 상한을 강제한다.
- HTTPS 는 `site_address` 를 도메인으로 지정해야 켜진다(기본은 평문 HTTP).
- A1(ARM) 인스턴스는 리전에 따라 용량 부족(`Out of host capacity`)이 날 수 있다. 그때는 `instance_shape = "VM.Standard.E2.1.Micro"` 로 바꾼다(단, 이 shape 는 Flex 가 아니라 OCPU·메모리 변수를 무시하고, 1GB 메모리라 빠듯하다).
