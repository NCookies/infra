variable "region" {
  description = "OCI 리전 식별자 (예: ap-chuncheon-1)"
  type        = string
}

variable "oci_config_profile" {
  description = "~/.oci/config 의 프로파일 이름"
  type        = string
  default     = "DEFAULT"
}

variable "compartment_ocid" {
  description = "리소스를 만들 컴파트먼트 OCID (루트 테넌시 OCID 도 가능)"
  type        = string
}

variable "name_prefix" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "infra"
}

variable "ssh_public_key" {
  description = "인스턴스에 등록할 SSH 공개키 내용 (ssh-ed25519 AAAA...)"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "SSH(22) 를 허용할 CIDR. 내 공인 IP/32 로 좁힐 것"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_shape" {
  description = "인스턴스 shape. 무료 한도는 VM.Standard.A1.Flex(ARM) 또는 VM.Standard.E2.1.Micro"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Flex shape 의 OCPU 수"
  type        = number
  default     = 1
}

variable "instance_memory_gbs" {
  description = "Flex shape 의 메모리(GB)"
  type        = number
  default     = 6
}

variable "boot_volume_gbs" {
  description = "부트 볼륨 크기(GB)"
  type        = number
  default     = 50
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "site_address" {
  description = "Caddy 가 서비스할 주소. 도메인이면 자동 HTTPS, 비우면 ':80' 평문 HTTP"
  type        = string
  default     = ":80"
}

variable "receiver_image" {
  description = "수신 서버 도커 이미지 (예: ghcr.io/<user>/receiver:latest)"
  type        = string
}

variable "receiver_api_token" {
  description = "수신 API 공유 토큰 (앱이 X-Api-Token 헤더로 보냄)"
  type        = string
  sensitive   = true
}

variable "watchtower_poll_interval" {
  description = "watchtower 이미지 갱신 확인 간격(초). 개발 중 테스트할 때만 줄인다"
  type        = number
  default     = 7200
}

variable "retention_days" {
  description = "오류 로그·진단 번들 자동 삭제까지의 일수(docs/privacy.md 의 보관 기간과 같아야 한다)"
  type        = number
  default     = 90
}
