#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

# LangChain 관련 모듈
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser


def load_results(results_dir):
    """3개 도구의 결과 파일 로드"""
    results = {}

    try:
        with open(f"{results_dir}/sonar-results.json") as f:
            results['sonar'] = json.load(f)

        with open(f"{results_dir}/codeql-results.sarif") as f:
            results['codeql'] = json.load(f)

        with open(f"{results_dir}/semgrep-results.json") as f:
            results['semgrep'] = json.load(f)
    except FileNotFoundError as e:
        print(f"❌ Error: {e.filename} not found")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"❌ Error: Invalid JSON in file - {e}")
        sys.exit(1)

    return results


def summarize_results(results):
    """데이터 전처리 - AI 분석에 필요한 핵심 정보만 추출"""
    summary = {
        'sonar': {
            'total': len(results['sonar'].get('issues', [])),
            'issues': [
                {
                    'rule': i.get('rule', 'Unknown'),
                    'message': i.get('message', ''),
                    'severity': i.get('severity', 'info')
                }
                for i in results['sonar'].get('issues', [])
            ]
        },
        'codeql': {
            'total': len(results['codeql']['runs'][0].get('results', [])),
            'issues': [
                {
                    'ruleId': r.get('ruleId', 'Unknown'),
                    'message': r.get('message', {}).get('text', '')
                }
                for r in results['codeql']['runs'][0].get('results', [])
            ]
        },
        'semgrep': {
            'total': len(results['semgrep'].get('results', [])),
            'issues': [
                {
                    'path': r.get('path', 'Unknown'),
                    'message': r.get('extra', {}).get('message', ''),
                    'severity': r.get('extra', {}).get('severity', 'WARNING')
                }
                for r in results['semgrep'].get('results', [])
            ]
        }
    }
    return summary


def analyze_with_langchain(results, api_key):
    """LangChain을 이용한 통합 보안 분석"""

    # 1. Claude 모델 설정
    model = ChatAnthropic(
        model="claude-sonnet-4-20250514",  # 최신 Sonnet 4.5 모델
        anthropic_api_key=api_key,
        temperature=0,  # 보안 분석은 일관성 중요 → 무작위성 제거
        max_tokens=4000  # 상세한 리포트 작성을 위해 토큰 증가
    )

    # 2. 프롬프트 템플릿 정의
    template = """당신은 금융권 DevSecOps 보안 전문가입니다.
다음 3개의 보안 스캔 도구 결과를 종합 분석하여 실무에 바로 적용 가능한 리포트를 작성하세요.

📌 **분석 요구사항:**
1. 중복된 이슈는 제거하고 통합
2. 심각도 순으로 정렬 (Critical > High > Medium > Low)
3. 각 이슈마다 구체적인 해결 방법 제시
4. 금융권 보안 규정(전자금융감독규정) 관점에서 평가

---

## 📊 SonarQube 분석 결과 ({sonar_total}개 이슈)
{sonar_data}

## 🔍 CodeQL 분석 결과 ({codeql_total}개 이슈)
{codeql_data}

## 🎯 Semgrep 분석 결과 ({semgrep_total}개 이슈)
{semgrep_data}

---

**아래 형식으로 마크다운 리포트를 작성하세요:**

# 🔒 통합 보안 분석 리포트

## 📊 전체 요약
- 총 발견 이슈 수:
- 심각도별 분포:
- 주요 취약점 유형:

## 🚨 Critical/High 우선순위 이슈
(각 이슈마다 아래 포함)
- **이슈명**:
- **위험도**:
- **영향 범위**:
- **해결 방법**:
- **관련 규정**: (해당 시)

## ⚠️ Medium 이슈

## ℹ️ Low/Info 이슈

## ✅ 종합 권장사항
1. 즉시 조치 필요 항목
2. 단기 개선 항목 (1주 이내)
3. 중장기 개선 항목

## 📈 보안 점수 평가
(A~F 등급으로 평가하고 근거 제시)
"""

    prompt = ChatPromptTemplate.from_template(template)

    # 3. LangChain 파이프라인 구성
    # prompt → model → text 추출 순서로 자동 실행
    chain = prompt | model | StrOutputParser()

    # 4. 데이터 준비 및 실행
    summary = summarize_results(results)

    print("🤖 Claude API 호출 중... (약 10-30초 소요)")

    try:
        response = chain.invoke({
            "sonar_total": summary['sonar']['total'],
            "sonar_data": json.dumps(summary['sonar']['issues'], indent=2, ensure_ascii=False),
            "codeql_total": summary['codeql']['total'],
            "codeql_data": json.dumps(summary['codeql']['issues'], indent=2, ensure_ascii=False),
            "semgrep_total": summary['semgrep']['total'],
            "semgrep_data": json.dumps(summary['semgrep']['issues'], indent=2, ensure_ascii=False)
        })
    except Exception as e:
        print(f"❌ Claude API 호출 실패: {e}")
        sys.exit(1)

    return response


def save_report(report, results_dir):
    """분석 리포트를 파일로 저장"""
    output_path = Path(results_dir) / "final-report.md"

    try:
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(report)
        print(f"\n✅ 리포트 저장 완료: {output_path}")
    except IOError as e:
        print(f"❌ 파일 저장 실패: {e}")
        sys.exit(1)


def main():
    """메인 실행 로직"""

    # 명령행 인자 검증
    if len(sys.argv) < 2:
        print("Usage: python llm-analyzer.py <results-directory>")
        print("Example: python llm-analyzer.py ./scan-results")
        sys.exit(1)

    results_dir = sys.argv[1]

    # 디렉토리 존재 확인
    if not os.path.isdir(results_dir):
        print(f"❌ Error: Directory '{results_dir}' does not exist")
        sys.exit(1)

    # API 키 확인
    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        print("❌ Error: ANTHROPIC_API_KEY 환경변수가 설정되지 않았습니다")
        print("설정 방법: export ANTHROPIC_API_KEY='your-api-key'")
        sys.exit(1)

    print("=" * 80)
    print("🔐 Dark Mac & Cheese - 통합 보안 분석 시작")
    print("=" * 80)

    # 1. 결과 파일 로드
    print("\n📂 보안 스캔 결과 로딩 중...")
    results = load_results(results_dir)
    print("   ✓ SonarQube, CodeQL, Semgrep 결과 로드 완료")

    # 2. LangChain으로 분석
    print("\n🤖 LangChain + Claude 4.5 Sonnet 분석 중...")
    report = analyze_with_langchain(results, api_key)

    # 3. 결과 출력
    print("\n" + "=" * 80)
    print(report)
    print("=" * 80)

    # 4. 파일 저장
    save_report(report, results_dir)

    print("\n🎉 분석 완료!")


if __name__ == '__main__':
    main()
