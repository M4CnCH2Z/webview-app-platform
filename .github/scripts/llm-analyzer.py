import os
import json
import glob
import sys
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import PromptTemplate
from langchain_core.output_parsers import JsonOutputParser

#입력 디렉토리(scan-results 같은 곳)를 받아서 “중복 제거 + SG용 요약 JSON 생성”을 수행하는 함수
def run_deduplication(input_dir):
    # 1. 스캔 결과 파일 수집
    # input_dir 안의 *.json 파일을 전부 찾음.
    json_files = glob.glob(os.path.join(input_dir, "*.json"))
    all_findings = []

    # 찾은 json 파일들 중에서 deduplicated-results.json과 sg-verdict.json은 제외하고 읽음
    for file_path in json_files:
        if "deduplicated-results.json" in file_path or "sg-verdict.json" in file_path:
            continue
        try:
            with open(file_path, "r", encoding="utf-8") as f: #utf-8로 읽기 
                all_findings.append({
                    "source": os.path.basename(file_path), #파일명만 저장 
                    "data": json.load(f) #json 데이터 파싱 
                })
        except Exception as e: # 실패한 파일은 건너뛰고 로그만 찍음(프로그램 전체는 계속 진행)
            print(f"{file_path} 읽기 실패: {e}")

    if not all_findings:
        print("분석할 결과 파일이 없습니다.")
        return

    # 2. JsonOutputParser 설정 (SG 규격 강제)
    # LLM 출력물을 JSON으로 받기 위한 파서
    parser = JsonOutputParser()

    # 3. 프롬프트 설정 (SG API 규격 주입)
    # 클로드에게 중복 제거 후 반드시 'summary' 숫자를 세라고 명령합니다.
    prompt = PromptTemplate(
        template="""당신은 숙련된 보안 엔지니어입니다. 
다음 보안 도구들의 결과에서 중복을 제거하고, Security Gate(SG) API 전송을 위한 요약본을 만드세요.

[수행 지침]
1. 여러 도구에서 발견된 동일한 파일/라인의 이슈는 하나로 합치세요.
2. 중복 제거된 최종 이슈들을 바탕으로 등급별(Critical, High, Medium, Low) 개수를 정확히 세세요.
3. 결과는 반드시 아래의 JSON 구조를 유지해야 합니다.

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

    # 4. 클로드 호출 (최신 모델 사용)
    model = ChatAnthropic(model="claude-sonnet-4-20250514", temperature=0)
    chain = prompt | model | parser

    print("클로드가 중복 제거 및 SG 요약 생성을 시작합니다...")

    try:
        # 분석 실행
        output_data = chain.invoke({"all_findings": json.dumps(all_findings, ensure_ascii=False)})

        # 결과 검증: summary 필드 확인
        if "summary" not in output_data:
            print("경고: 'summary' 필드가 누락되어 기본값으로 설정합니다.")
            output_data["summary"] = {
                "tool": "Claude-AI-Analyzer",
                "tool_version": "3.5",
                "new_critical": 0,
                "new_high": 0,
                "new_medium": 0,
                "new_low": 0
            }

        # 5. 결과 저장 (이 파일이 나중에 sg-upload.sh의 소스가 됨)
        output_path = os.path.join(input_dir, "deduplicated-results.json")
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(output_data, f, indent=2, ensure_ascii=False)

        print(f"✅ SG용 요약 생성 완료! 저장됨: {output_path}")
        print(f"   - Critical: {output_data['summary'].get('new_critical', 0)}")
        print(f"   - High: {output_data['summary'].get('new_high', 0)}")
        print(f"   - Medium: {output_data['summary'].get('new_medium', 0)}")
        print(f"   - Low: {output_data['summary'].get('new_low', 0)}")

    except Exception as e:
        print(f"❌ 분석 중 에러 발생: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "scan-results"
    run_deduplication(path)