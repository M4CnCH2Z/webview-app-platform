# 실패 시 시큐어코딩 포함 리포트 작성
import os
import json
import sys
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import PromptTemplate

def run_final_report(results_path, verdict_path):
    # 1. 파일 읽기
    try:
        with open(results_path, "r", encoding="utf-8") as f:
            dedup_data = json.load(f)
        with open(verdict_path, "r", encoding="utf-8") as f:
            verdict_data = json.load(f)
    except Exception as e:
        print(f"파일 읽기 오류: {e}")
        return

    # 2. 클로드에게 줄 데이터 정리
    findings = dedup_data.get("findings", [])
    summary = dedup_data.get("summary", {})
    
    if not findings:
        print("분석할 취약점이 없습니다.")
        return

    # 3. 프롬프트 설정 (개발자 친화적인 솔루션 중심)
    prompt = PromptTemplate(
        template="""당신은 시큐어 코딩 전문가입니다. 
Security Gate(SG) 판정 결과 **불합격(FAIL)**이 발생했습니다. 
개발자가 이슈를 즉시 수정할 수 있도록 아래 데이터를 바탕으로 상세 가이드를 작성하세요.

[데이터]
- 요약: {summary}
- 발견된 취약점 리스트: {findings}

[작성 지침]
1. 말투는 친절하고 전문적인 톤으로 유지하세요.
2. 각 취약점별로 다음 형식을 따르세요:
   - **[위치]**: 파일명 및 라인 번호
   - **[취약점 설명]**: 어떤 보안 위험이 있는지 짧고 명확하게 설명
   - **[시큐어 코딩 가이드]**: '잘못된 코드' vs '수정된 코드' 예시를 마크다운 코드 블록으로 제시
3. 마지막에는 전체적인 보안 품질 향상을 위한 조언을 한 줄 추가하세요.
4. 결과는 GitHub PR 댓글에 바로 붙일 수 있도록 마크다운(Markdown) 형식으로만 출력하세요.

결과물:""",
        input_variables=["summary", "findings"],
    )

    # 4. 클로드 호출 (최신 모델 사용)
    model = ChatAnthropic(model="claude-sonnet-4-20250514", temperature=0)

    print("클로드가 최종 시큐어 코딩 가이드를 작성 중입니다...")

    try:
        # 분석 실행 (결과가 마크다운 텍스트이므로 Parser 없이 스트링으로 받음)
        response = model.invoke(prompt.format(
            summary=json.dumps(summary, ensure_ascii=False),
            findings=json.dumps(findings, ensure_ascii=False)
        ))

        # 5. 마크다운 파일로 저장
        # response는 AIMessage 객체이므로 .content로 텍스트 추출
        output_path = "final-report.md"
        with open(output_path, "w", encoding="utf-8") as f:
            # AIMessage 객체에서 content 추출
            content = response.content if hasattr(response, 'content') else str(response)
            f.write(content)

        print(f"최종 리포트 생성 완료: {output_path}")
        print(f"   총 {len(findings)}개 취약점에 대한 시큐어 코딩 가이드가 생성되었습니다.")

    except Exception as e:
        print(f"리포트 생성 중 에러 발생: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    # 실행 시 인자로 받은 경로 사용
    results_json = sys.argv[1] if len(sys.argv) > 1 else "final-input/deduplicated-results.json"
    verdict_json = sys.argv[2] if len(sys.argv) > 2 else "final-input/sg-verdict.json"
    run_final_report(results_json, verdict_json)