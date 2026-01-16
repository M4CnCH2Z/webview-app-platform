import os
import json
import glob
import sys
import time
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import PromptTemplate
from langchain_core.output_parsers import JsonOutputParser

# =========================================================
# [설정] 보안 규칙 화이트리스트 및 키워드 (CodeQL용)
# =========================================================
SECURITY_RULES_WHITELIST = {
    # [Java]
    'java/sql-injection', 'java/log-injection', 'java/command-injection',
    'java/xpath-injection', 'java/ldap-injection', 'java/path-injection',
    'java/xss', 'java/spring-disabled-csrf-protection', 'java/unsafe-deserialization',
    'java/zipslip', 'java/path-traversal', 'java/ssrf', 'java/xxe',
    'java/weak-cryptographic-algorithm', 'java/insecure-randomness',
    'java/hardcoded-credential', 'java/cleartext-storage-in-cookie',
    'java/android/backup-enabled', 'java/rsa-without-oaep',
    
    # [JS/TS]
    'js/sql-injection', 'js/command-injection', 'js/xss',
    'js/path-injection', 'js/prototype-pollution',
}

SECURITY_KEYWORDS = [
    'injection', 'xss', 'csrf', 'xxe', 'ssrf', 
    'deserialization', 'traversal', 'credential', 
    'password', 'secret', 'crypto', 'weak', 'security'
]

# 심각도 우선순위 (낮을수록 중요)
SEVERITY_ORDER = {
    "CRITICAL": 0, "BLOCKER": 0,
    "HIGH": 1, "MAJOR": 1, "ERROR": 1,
    "MEDIUM": 2, "WARNING": 2,
    "LOW": 3, "MINOR": 3, "INFO": 3, "NOTE": 3, "NONE": 4
}

# =========================================================
# [함수] 보안 타겟 판별 로직
# =========================================================
def is_security_target(rule_id):
    """CodeQL Rule ID가 우리가 찾는 보안 이슈인지 확인"""
    if not rule_id: return False
    rule_lower = rule_id.lower()
    
    # 1. 화이트리스트 확인
    if rule_lower in SECURITY_RULES_WHITELIST:
        return True
    # 2. 키워드 매칭
    if any(kw in rule_lower for kw in SECURITY_KEYWORDS):
        return True
    return False

def normalize_severity(val):
    """모든 도구의 심각도를 표준(CRITICAL/HIGH/MEDIUM/LOW)으로 변환"""
    val = val.upper()
    if val in ["BLOCKER", "CRITICAL"]: return "CRITICAL"
    if val in ["ERROR", "HIGH", "MAJOR"]: return "HIGH"
    if val in ["WARNING", "MEDIUM"]: return "MEDIUM"
    return "LOW"

# =========================================================
# [메인 로직] 데이터 추출 및 필터링
# =========================================================
def extract_key_findings(data, source_filename):
    """각 도구별로 핵심 정보만 추출하고 LOW 등급은 즉시 폐기"""
    findings = []
    
    # 1. SonarQube 처리
    if "issues" in data:
        for issue in data.get("issues", []):
            raw_severity = issue.get("severity", "INFO").upper()
            
            # [필터링 1] Sonar는 API에서 이미 걸렀지만 한번 더 안전장치
            if raw_severity in ["LOW", "INFO", "MINOR", "NOTE"]:
                continue

            findings.append({
                "source": "SonarQube",
                "severity": normalize_severity(raw_severity),
                "message": issue.get("message", "")[:300],
                "file": issue.get("component", "").split(":")[-1],
                "line": issue.get("line", 0),
                "rule": issue.get("rule", "")
            })
    
    # 2. SARIF 처리 (Semgrep / CodeQL)
    elif "runs" in data:
        for run in data.get("runs", []):
            tool_name = run.get("tool", {}).get("driver", {}).get("name", "Unknown")
            
            # CodeQL일 경우: Rule 정의(rules)를 먼저 매핑해둠 (Properties 점수 확인용)
            rules_map = {}
            if "CodeQL" in tool_name: # CodeQL 문자열이 포함되어 있으면
                for r in run.get("tool", {}).get("driver", {}).get("rules", []):
                    rules_map[r["id"]] = r

            for result in run.get("results", []):
                rule_id = result.get("ruleId", "")
                level = result.get("level", "warning") # 기본값 warning
                
                final_severity = "LOW" # 초기화

                # --- [CodeQL 전용 로직] ---
                if "CodeQL" in tool_name:
                    # (1) 화이트리스트/키워드 검사 (보안 이슈 아니면 버림)
                    if not is_security_target(rule_id):
                        continue
                    
                    # (2) 진짜 심각도(Score) 확인
                    rule_prop = rules_map.get(rule_id, {}).get("properties", {})
                    score = float(rule_prop.get("security-severity", 0.0))
                    
                    if score >= 9.0: final_severity = "CRITICAL"
                    elif score >= 7.0: final_severity = "HIGH"
                    elif score >= 4.0: final_severity = "MEDIUM"
                    else: final_severity = "LOW"
                    
                # --- [Semgrep/기타 전용 로직] ---
                else:
                    final_severity = normalize_severity(level)

                # [필터링 2] 여기서 최종 확인: LOW는 무조건 버림
                if final_severity == "LOW":
                    continue

                # 위치 정보 추출
                location = result.get("locations", [{}])[0].get("physicalLocation", {})
                findings.append({
                    "source": tool_name,
                    "severity": final_severity,
                    "message": result.get("message", {}).get("text", "")[:300],
                    "file": location.get("artifactLocation", {}).get("uri", ""),
                    "line": location.get("region", {}).get("startLine", 0),
                    "rule": rule_id
                })
    
    return findings

def run_deduplication(input_dir):
    """중복 제거 + SG용 요약 JSON 생성"""
    
    # 1. 파일 수집 (json + sarif) 
    json_files = glob.glob(os.path.join(input_dir, "*.json"))
    json_files.extend(glob.glob(os.path.join(input_dir, "*.sarif")))
    
    all_findings = []
    print(f" 분석 경로: {input_dir}")

    for file_path in json_files:
        if "deduplicated-results.json" in file_path or "sg-verdict.json" in file_path:
            continue
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                source_name = os.path.basename(file_path)
                
                extracted = extract_key_findings(data, source_name)
                
                if extracted:
                    all_findings.extend(extracted)
                    print(f"   - {source_name}: {len(extracted)}개 유효 이슈")
                else:
                    print(f"   - {source_name}: 유효 이슈 없음 (필터링됨)")
        except Exception as e:
            print(f" {file_path} 읽기 실패: {e}")

    if not all_findings:
        print(" 분석할 보안 이슈가 없습니다.")
        # 빈 결과 파일 생성 (워크플로우 에러 방지)
        with open(os.path.join(input_dir, "deduplicated-results.json"), "w") as f:
            json.dump({"summary": {"tool": "Claude-AI-Analyzer", "tool_version": "1.0.0", "new_critical":0, "new_high":0, "new_medium":0, "new_low":0}, "findings": []}, f)
        return

    # 2. 총 개수 제한
    all_findings = sorted(all_findings, key=lambda x: SEVERITY_ORDER.get(x.get("severity", "UNKNOWN"), 99))
    if len(all_findings) > 50:
        print(f" 총 {len(all_findings)}개 발견 → 상위 50개만 AI 분석")
        all_findings = all_findings[:50]

    # 3. 프롬프트 설정
    parser = JsonOutputParser()
    prompt = PromptTemplate(
        template="""당신은 최고의 보안 전문가입니다. 
다음은 SAST 도구(SonarQube, CodeQL, Semgrep)가 탐지한 보안 취약점들입니다.
이미 1차 필터링은 거쳤으나, 중복이나 오탐이 있을 수 있습니다.

[목표]
중복을 제거하고, 개발자가 당장 고쳐야 할 진짜 보안 이슈만 남긴 JSON을 작성하세요.

[필수 지침]
1. **중복 제거**: 같은 파일, 같은 라인, 같은 문제라면 도구가 달라도 하나로 합치세요.
2. **설명**: description은 개발자가 이해하기 쉽게 "문제점"과 "해결방안"을 한글로 요약하세요.
3. **등급**: AI의 판단하에 위험하지 않다면 과감히 제외해도 됩니다.
4. **JSON 포맷**: 아래 포맷을 반드시 따르세요.

[입력 데이터]
{all_findings}

[출력 포맷]
{{
  "summary": {{
    "tool": "Claude-AI-Analyzer",
    "tool_version": "1.0.0",
    "new_critical": 0,
    "new_high": 0,
    "new_medium": 0,
    "new_low": 0
  }},
  "findings": [
    {{
      "title": "이슈 제목",
      "severity": "CRITICAL/HIGH/MEDIUM/LOW",
      "file": "파일 경로",
      "line": 10,
      "description": "상세 설명"
    }}
  ]
}}
""",
        input_variables=["all_findings"],
    )

    # 4. 클로드 호출
    # 모델명은 사용 가능한 최신 모델로 지정하세요.
    model = ChatAnthropic(model="claude-sonnet-4-20250514", temperature=0) 
    chain = prompt | model | parser

    print(f" AI 분석 시작... ({len(all_findings)}개 항목)")

    try:
        output_data = chain.invoke({"all_findings": json.dumps(all_findings, ensure_ascii=False)})

        output_path = os.path.join(input_dir, "deduplicated-results.json")
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(output_data, f, indent=2, ensure_ascii=False)

        print(f" 분석 완료! 결과 저장됨: {output_path}")
        s = output_data.get("summary", {})
        print(f"    결과: Critical({s.get('new_critical',0)}) High({s.get('new_high',0)}) Medium({s.get('new_medium',0)})")

    except Exception as e:
        print(f" AI 분석 중 에러 발생: {e}")
        with open(os.path.join(input_dir, "deduplicated-results.json"), "w") as f:
            json.dump({"error": str(e), "findings": []}, f)

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "scan-results"
    run_deduplication(path)