import os
import json
import glob
import sys
import time
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import PromptTemplate
from langchain_core.output_parsers import JsonOutputParser

# 심각도 우선순위 (낮을수록 중요)
SEVERITY_ORDER = {
    "CRITICAL": 0, "BLOCKER": 0,
    "HIGH": 1, "MAJOR": 1, "ERROR": 1,
    "MEDIUM": 2, "MINOR": 2, "WARNING": 2,
    "LOW": 3, "INFO": 3, "NOTE": 3
}

def extract_key_findings(data, source):
    """각 도구별로 핵심 정보만 추출 (토큰 절약)"""
    findings = []
    
    # SonarQube 형식
    if "issues" in data:
        issues = data.get("issues", [])
        # 심각도 순 정렬
        issues = sorted(issues, key=lambda x: SEVERITY_ORDER.get(x.get("severity", "").upper(), 99))
        
        for issue in issues[:50]:  # 도구당 최대 50개
            findings.append({
                "source": source,
                "severity": issue.get("severity", "UNKNOWN"),
                "message": issue.get("message", "")[:200],  # 200자 제한
                "file": issue.get("component", "").split(":")[-1],
                "line": issue.get("line", 0),
                "rule": issue.get("rule", "")
            })
    
    # SARIF 형식 (Semgrep, CodeQL)
    elif "runs" in data:
        all_results = []
        for run in data.get("runs", []):
            all_results.extend(run.get("results", []))
        
        # 심각도 순 정렬
        all_results = sorted(all_results, key=lambda x: SEVERITY_ORDER.get(x.get("level", "warning").upper(), 99))
        
        for result in all_results[:50]:  # 도구당 최대 50개
            location = result.get("locations", [{}])[0].get("physicalLocation", {})
            findings.append({
                "source": source,
                "severity": result.get("level", "warning").upper(),
                "message": result.get("message", {}).get("text", "")[:200],
                "file": location.get("artifactLocation", {}).get("uri", ""),
                "line": location.get("region", {}).get("startLine", 0),
                "rule": result.get("ruleId", "")
            })
    
    return findings


def run_deduplication(input_dir):
    """중복 제거 + SG용 요약 JSON 생성"""
    
    # 1. 스캔 결과 파일 수집 및 핵심 정보 추출
    json_files = glob.glob(os.path.join(input_dir, "*.json"))
    all_findings = []

    for file_path in json_files:
        if "deduplicated-results.json" in file_path or "sg-verdict.json" in file_path:
            continue
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                source = os.path.basename(file_path)
                # 핵심 정보만 추출
                findings = extract_key_findings(data, source)
                all_findings.extend(findings)
                print(f"📁 {source}: {len(findings)}개 추출")
        except Exception as e:
            print(f"⚠️ {file_path} 읽기 실패: {e}")

    if not all_findings:
        print("분석할 결과 파일이 없습니다.")
        return

    # 2. 총 개수 제한 (심각도 순 정렬 후 상위 100개)
    if len(all_findings) > 100:
        all_findings = sorted(all_findings, key=lambda x: SEVERITY_ORDER.get(x.get("severity", "UNKNOWN").upper(), 99))
        print(f"⚠️ {len(all_findings)}개 발견 → 심각도 높은 순 100개만 분석")
        all_findings = all_findings[:100]

    # 3. 프롬프트 설정
    parser = JsonOutputParser()
    prompt = PromptTemplate(
        template="""당신은 숙련된 보안 엔지니어입니다. 
다음 보안 도구들의 결과에서 중복을 제거하고, Security Gate(SG) API 전송을 위한 요약본을 만드세요.

[수행 지침]
1. 동일한 파일/라인의 이슈는 하나로 합치세요.
2. 등급별(Critical, High, Medium, Low) 개수를 정확히 세세요.
3. 결과는 반드시 아래 JSON 구조를 유지하세요.

[필수 JSON 구조]
{{
  "summary": {{
    "tool": "Claude-AI-Analyzer",
    "tool_version": "4.5",
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
      "line": "라인 번호",
      "description": "상세 설명"
    }}
  ]
}}

{format_instructions}

데이터:
{all_findings}""",
        input_variables=["all_findings"],
        partial_variables={"format_instructions": parser.get_format_instructions()},
    )

    # 4. 클로드 호출 (재시도 로직 포함)
    model = ChatAnthropic(model="claude-sonnet-4-20250514", temperature=0)
    chain = prompt | model | parser

    print(f"🤖 클로드 분석 시작... (총 {len(all_findings)}개 findings)")

    max_retries = 3
    for attempt in range(max_retries):
        try:
            output_data = chain.invoke({"all_findings": json.dumps(all_findings, ensure_ascii=False)})

            # summary 필드 검증
            if "summary" not in output_data:
                output_data["summary"] = {
                    "tool": "Claude-AI-Analyzer",
                    "tool_version": "4.5",
                    "new_critical": 0,
                    "new_high": 0,
                    "new_medium": 0,
                    "new_low": 0
                }

            # 결과 저장
            output_path = os.path.join(input_dir, "deduplicated-results.json")
            with open(output_path, "w", encoding="utf-8") as f:
                json.dump(output_data, f, indent=2, ensure_ascii=False)

            print(f"✅ 완료! 저장됨: {output_path}")
            print(f"   - Critical: {output_data['summary'].get('new_critical', 0)}")
            print(f"   - High: {output_data['summary'].get('new_high', 0)}")
            print(f"   - Medium: {output_data['summary'].get('new_medium', 0)}")
            print(f"   - Low: {output_data['summary'].get('new_low', 0)}")
            return  # 성공 시 종료

        except Exception as e:
            if "rate_limit" in str(e).lower() and attempt < max_retries - 1:
                wait_time = 60 * (attempt + 1)
                print(f"⏳ Rate limit 도달. {wait_time}초 후 재시도... ({attempt + 1}/{max_retries})")
                time.sleep(wait_time)
            else:
                print(f"❌ 에러 발생: {e}")
                sys.exit(1)


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "scan-results"
    run_deduplication(path)