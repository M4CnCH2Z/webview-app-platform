import React from 'react';
import ReactDOM from 'react-dom/client';
import { HelmetProvider } from 'react-helmet-async'; // 보안 헤더 관리
import './index.css';
import App from './App';
import reportWebVitals from './reportWebVitals';

// 1. 보안 콘솔 경고 (브라우저 콘솔을 통한 XSS 공격 방어 안내)
if (process.env.NODE_ENV === 'production') {
  console.log(
    "%c주의! 이곳은 개발자 도구입니다.",
    "color: red; font-size: 30px; font-weight: bold;"
  );
  console.log("여기에 알 수 없는 코드를 복사해서 붙여넣으면 해커가 계정을 탈취할 수 있습니다.");
}

const root = ReactDOM.createRoot(document.getElementById('root'));

root.render(
  // 2. StrictMode: 잠재적 보안 취약점 및 구식 API 사용 감지
  <React.StrictMode>
    {/* 3. HelmetProvider: App.js와 각 페이지에서 보안 헤더(CSP 등)를 동적으로 제어 */}
    <HelmetProvider>
      <App />
    </HelmetProvider>
  </React.StrictMode>
);

// 4. 성능 측정 보고 (보안상 필요 없는 경우 production 환경에서 제거 권장)
if (process.env.NODE_ENV !== 'production') {
  reportWebVitals(console.log);
}