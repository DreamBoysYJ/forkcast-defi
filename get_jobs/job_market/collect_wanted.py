#!/usr/bin/env python3
"""
한국 백엔드 채용 공고 스택 통계 수집기 (원티드)

목적: "눈으로 슥 읽는 편향"을 빈도 통계로 대체한다.
      신입~주니어(0~3년) 기준으로, 3개 트랙(블록체인 백엔드 / 스마트 컨트랙트 / 웹 백엔드)별
      요구 스택 빈도를 집계하고, 김영주 프로필 대비 갭을 뽑는다.

검증된 원티드 엔드포인트만 사용:
  - 목록: GET /api/chaos/navigation/v1/results?job_group_id=518 (개발 직군), 페이지네이션
  - 상세: GET /api/chaos/jobs/v1/{id}/details  (JD 전체 텍스트)
  ※ navigation API의 query 파라미터는 무시되므로, 트랙 분류/스택 추출은 클라이언트에서 키워드로 처리.

특징:
  - stdlib만 사용 (urllib). pip 설치 불필요.
  - 상세 응답은 out/cache/ 에 캐싱 → 재실행 시 재수집 안 함.
  - 산출물: out/report.md, out/freq_<track>.csv

사용:
  python3 collect_wanted.py --max-list 1200 --max-detail 500
"""
import argparse
import csv
import json
import os
import re
import time
import urllib.parse
import urllib.request
from collections import Counter, defaultdict

BASE = "https://www.wanted.co.kr"
JOB_GROUP_DEV = 518  # 개발 직군
HEADERS = {"User-Agent": "Mozilla/5.0 (job-market-research; personal)"}
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
CACHE = os.path.join(OUT, "cache")

# ── 스택 사전: canonical 이름 -> 매칭 정규식(영문 word-boundary + 한글 동의어) ──
# 백엔드 채용에서 실제로 변별력 있는 항목 위주. 너무 흔한 git/linux 등은 제외.
STACK_PATTERNS = {
    # 언어
    "Java": r"\bjava\b(?!\s*script)",
    "Kotlin": r"\bkotlin\b|코틀린",
    "Python": r"\bpython\b|파이썬",
    "Go": r"\bgo(?:lang)?\b|\b고언어\b",
    "Node.js": r"\bnode\.?js\b|노드\.?js",
    "TypeScript": r"\btypescript\b|타입스크립트",
    "Rust": r"\brust\b|러스트",
    "C++": r"\bc\+\+\b",
    "Solidity": r"\bsolidity\b|솔리디티",
    # 백엔드 프레임워크
    "Spring": r"\bspring\b",
    "Spring Boot": r"spring\s*boot|스프링\s*부트",
    "JPA/Hibernate": r"\bjpa\b|hibernate|하이버네이트",
    "Django": r"\bdjango\b|장고",
    "FastAPI": r"\bfastapi\b",
    "Flask": r"\bflask\b",
    "Express": r"\bexpress(?:\.js)?\b",
    "NestJS": r"\bnest\.?js\b",
    # DB / 캐시 / 검색
    "MySQL": r"\bmysql\b|마이에스큐엘",
    "PostgreSQL": r"\bpostgre(?:sql)?\b|포스트그레",
    "MariaDB": r"\bmariadb\b",
    "Oracle": r"\boracle\b|오라클",
    "MongoDB": r"\bmongo(?:db)?\b|몽고",
    "Redis": r"\bredis\b|레디스",
    "Elasticsearch": r"\belastic\s*search\b|elasticsearch|엘라스틱",
    "Kafka": r"\bkafka\b|카프카",
    "RabbitMQ": r"\brabbitmq\b",
    # 인프라 / 클라우드 / 데브옵스
    "AWS": r"\baws\b|amazon\s*web",
    "GCP": r"\bgcp\b|google\s*cloud",
    "Azure": r"\bazure\b",
    "Docker": r"\bdocker\b|도커",
    "Kubernetes": r"\bkubernetes\b|\bk8s\b|쿠버네티스",
    "Terraform": r"\bterraform\b",
    "Jenkins": r"\bjenkins\b|젠킨스",
    "GitHub Actions": r"github\s*actions",
    "ArgoCD": r"\bargo\s*cd\b|argocd",
    "CI/CD": r"\bci/?cd\b|ci\s*/\s*cd",
    # 아키텍처 / API
    "MSA": r"\bmsa\b|마이크로\s*서비스|microservice",
    "REST API": r"\brest(?:ful)?\s*api\b|\brest\b",
    "GraphQL": r"\bgraphql\b",
    "gRPC": r"\bgrpc\b",
    "Event-Driven": r"event[-\s]?driven|이벤트\s*기반",
    "DDD": r"\bddd\b|도메인\s*주도",
    # 관측성
    "Prometheus": r"\bprometheus\b|프로메테우스",
    "Grafana": r"\bgrafana\b|그라파나",
    "Datadog": r"\bdatadog\b",
    "ELK": r"\belk\b|logstash|kibana",
    # 블록체인 / Web3
    "EVM": r"\bevm\b",
    "Foundry": r"\bfoundry\b",
    "Hardhat": r"\bhardhat\b",
    "ethers.js": r"\bethers(?:\.js)?\b",
    "web3.js": r"\bweb3\.?js\b",
    "web3j": r"\bweb3j\b",
    "Geth": r"\bgeth\b",
    "Smart Contract": r"smart\s*contract|스마트\s*컨트랙트",
    "Cosmos SDK": r"\bcosmos\s*sdk\b|코스모스",
    "Substrate": r"\bsubstrate\b",
    "Hyperledger": r"\bhyperledger\b|하이퍼레저",
    "The Graph": r"\bthe\s*graph\b|subgraph|서브그래프",
}
STACK_RE = {k: re.compile(v, re.IGNORECASE) for k, v in STACK_PATTERNS.items()}

# ── 트랙 분류 키워드 (제목+JD 텍스트에 매칭) ──
DOMAIN_BLOCKCHAIN = re.compile(
    r"블록체인|blockchain|\bweb3\b|디파이|\bdefi\b|크립토|crypto|암호화폐|\bdapp\b|\bnft\b|온체인|on-?chain",
    re.IGNORECASE,
)
CONTRACT_FOCUS = re.compile(
    r"solidity|솔리디티|스마트\s*컨트랙트|smart\s*contract|\bfoundry\b|\bhardhat\b|컨트랙트\s*개발|audit|감사",
    re.IGNORECASE,
)
WEB_BACKEND = re.compile(
    r"백엔드|back[-\s]?end|서버\s*개발|\bserver\b|\bapi\b|\bspring\b|\bjava\b|\bnode|\bdjango\b|서버\s*엔지니어",
    re.IGNORECASE,
)

# ── 김영주 보유 스택 (candidate-profile.md 기준) → 갭 분석용 ──
HAS = {
    "Java", "Spring", "Spring Boot", "JPA/Hibernate", "Python", "Go", "Node.js",
    "TypeScript", "Solidity", "PostgreSQL", "MongoDB", "GCP", "Docker", "Kubernetes",
    "Foundry", "ethers.js", "web3.js", "web3j", "Geth", "Smart Contract", "EVM",
    "Cosmos SDK", "REST API",
    # 약하게 보유(개인 프로젝트 수준)는 별도 표기
}
WEAK = {"Docker", "Kubernetes"}  # 운영 깊이 부족으로 표기


def fetch(url, retries=2):
    for i in range(retries + 1):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:
            if i == retries:
                print(f"  [fetch 실패] {url[:80]} :: {e}")
                return None
            time.sleep(0.5 * (i + 1))


def list_jobs(max_list):
    """개발 직군(518) 최신순 페이지네이션. 신입~주니어(annual_from<=3 or newbie)만 반환."""
    out, offset, limit = [], 0, 100
    while len(out) < max_list:
        params = {
            "job_group_id": JOB_GROUP_DEV, "country": "kr",
            "job_sort": "job.latest_order", "locations": "all",
            "years": -1, "limit": limit, "offset": offset,
        }
        url = f"{BASE}/api/chaos/navigation/v1/results?" + urllib.parse.urlencode(params)
        d = fetch(url)
        rows = (d or {}).get("data", [])
        if not rows:
            break
        for j in rows:
            af = j.get("annual_from")
            if j.get("is_newbie") or (af is not None and af <= 3):
                out.append(j)
        offset += limit
        time.sleep(0.15)
    return out[:max_list]


def get_detail_text(job_id):
    """상세 JD 전체를 평탄화한 텍스트. 캐싱."""
    cache_path = os.path.join(CACHE, f"{job_id}.json")
    d = None
    if os.path.exists(cache_path):
        try:
            with open(cache_path) as f:
                d = json.load(f)
        except (json.JSONDecodeError, ValueError):
            d = None  # 손상 캐시(동시 실행 등) → 재수집
    if d is None:
        d = fetch(f"{BASE}/api/chaos/jobs/v1/{job_id}/details")
        if d is None:
            return ""
        tmp = cache_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(d, f, ensure_ascii=False)
        os.replace(tmp, cache_path)  # 원자적 교체로 부분쓰기 방지
        time.sleep(0.15)
    # 모든 문자열 값을 재귀적으로 모아 하나의 텍스트로
    buf = []

    def walk(x):
        if isinstance(x, str):
            buf.append(x)
        elif isinstance(x, dict):
            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)

    walk(d)
    return "\n".join(buf)


def classify(title, jd):
    """트랙 분류. 우선순위: 컨트랙트 > 블록체인 백엔드 > 웹 백엔드 > (제외)."""
    blob = f"{title}\n{jd}"
    is_chain = bool(DOMAIN_BLOCKCHAIN.search(blob))
    is_contract = bool(CONTRACT_FOCUS.search(blob))
    is_web = bool(WEB_BACKEND.search(blob))
    if is_chain and is_contract:
        return "contract"      # B. 스마트 컨트랙트
    if is_chain and is_web:
        return "chain_backend"  # A. 블록체인 백엔드
    if is_contract:
        return "contract"
    if is_web:
        return "web_backend"    # C. 웹 백엔드
    return None                 # 프론트/AI/기타 → 제외


def extract_stacks(text):
    return {name for name, rx in STACK_RE.items() if rx.search(text)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-list", type=int, default=1200, help="목록 수집 상한")
    ap.add_argument("--max-detail", type=int, default=500, help="상세 조회 상한(요청 수 제한)")
    ap.add_argument("--jvm-only", action="store_true",
                    help="C.웹백엔드를 JVM(Java/Spring/Kotlin) 요구 공고로만 한정")
    args = ap.parse_args()

    os.makedirs(CACHE, exist_ok=True)

    print(f"[1/3] 개발 직군 목록 수집 (최신순, 신입~주니어 필터)...")
    jobs = list_jobs(args.max_list)
    print(f"  → 주니어-도달가능 공고 {len(jobs)}건")

    print(f"[2/3] 상세 JD 조회 + 트랙 분류 + 스택 추출 (상한 {args.max_detail})...")
    track_names = {
        "chain_backend": "A. 블록체인 백엔드",
        "contract": "B. 스마트 컨트랙트",
        "web_backend": "C. 웹 백엔드",
    }
    counts = {t: Counter() for t in track_names}        # 스택별 공고 수
    totals = Counter()                                   # 트랙별 공고 수
    cooc_spring = Counter()                              # (C) Spring 공고에서 함께 뜬 스택
    spring_total = 0
    sampled = []                                         # (track, title, company, stacks)

    for i, j in enumerate(jobs):
        if i >= args.max_detail:
            print(f"  (상세 조회 상한 {args.max_detail} 도달, 나머지 {len(jobs)-i}건 스킵)")
            break
        jd = get_detail_text(j["id"])
        title = j.get("position", "")
        track = classify(title, jd)
        if track is None:
            continue
        stacks = extract_stacks(f"{title}\n{jd}")
        if track == "web_backend" and args.jvm_only and not (
            stacks & {"Java", "Spring", "Spring Boot", "Kotlin", "JPA/Hibernate"}
        ):
            continue  # JVM 미요구 웹백엔드(Python/Node 등) 제외
        totals[track] += 1
        for s in stacks:
            counts[track][s] += 1
        if track == "web_backend" and "Spring" in stacks:
            spring_total += 1
            for s in stacks:
                if s != "Spring":
                    cooc_spring[s] += 1
        sampled.append((track, title, j.get("company", {}).get("name", ""), sorted(stacks)))

    print(f"[3/3] 리포트 작성...")
    write_report(track_names, counts, totals, cooc_spring, spring_total, len(jobs),
                 jvm_only=args.jvm_only)
    print(f"  → {os.path.join(OUT, 'report.md')}")


def write_report(track_names, counts, totals, cooc_spring, spring_total, n_junior, jvm_only=False):
    lines = []
    lines.append("# 한국 백엔드 채용 스택 통계 (원티드 · 신입~주니어 0~3년)\n")
    lines.append(f"- 데이터: 원티드 개발 직군(518) 최신순, 주니어-도달가능 {n_junior}건에서 트랙 분류\n")
    if jvm_only:
        lines.append("- **C.웹백엔드 = JVM(Java/Spring/Kotlin) 요구 공고로 한정** (Python/Node 단독 제외)\n")
    lines.append("- 한계: 원티드 단일 소스 / 최신순 스냅샷. 블록체인(A·B)은 한국 표본이 얇아 참고용.\n")

    for t, label in track_names.items():
        tot = totals[t]
        lines.append(f"\n## {label} — {tot}건\n")
        if tot == 0:
            lines.append("_표본 없음._\n")
            continue
        lines.append("| 스택 | 공고 수 | 비율 | 보유 |")
        lines.append("|---|---:|---:|:--:|")
        for stack, c in counts[t].most_common(30):
            pct = f"{100*c/tot:.0f}%"
            mark = "✅" if stack in HAS else "❌"
            if stack in WEAK:
                mark = "△"
            lines.append(f"| {stack} | {c} | {pct} | {mark} |")

    # 갭 분석 (웹 백엔드 기준 — 표본 가장 큼)
    t = "web_backend"
    if totals[t]:
        lines.append("\n## 🎯 갭 분석 — C.웹 백엔드 (자주 요구되는데 미보유)\n")
        lines.append("| 스택 | 요구 비율 | 상태 |")
        lines.append("|---|---:|---|")
        for stack, c in counts[t].most_common(40):
            pct = 100 * c / totals[t]
            if pct < 15:
                continue
            if stack in HAS and stack not in WEAK:
                continue
            status = "△ 보유하나 깊이 부족" if stack in WEAK else "❌ 미보유 → 학습 후보"
            lines.append(f"| {stack} | {pct:.0f}% | {status} |")

    # Spring 공동출현
    if spring_total:
        lines.append(f"\n## 🔗 Spring 공고({spring_total}건)에서 함께 요구된 스택\n")
        lines.append("> '스프링 다음에 뭘 묶어서 공부할지' 우선순위.\n")
        lines.append("| 스택 | 동반 비율 |")
        lines.append("|---|---:|")
        for stack, c in cooc_spring.most_common(20):
            lines.append(f"| {stack} | {100*c/spring_total:.0f}% |")

    with open(os.path.join(OUT, "report.md"), "w") as f:
        f.write("\n".join(lines) + "\n")

    # CSV
    for t, label in track_names.items():
        if not totals[t]:
            continue
        with open(os.path.join(OUT, f"freq_{t}.csv"), "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["stack", "count", "pct", "has"])
            for stack, c in counts[t].most_common():
                w.writerow([stack, c, round(100 * c / totals[t], 1), stack in HAS])


if __name__ == "__main__":
    main()
