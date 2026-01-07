import axios from 'axios';

// 1. 인스턴스 설정 보안화
const api = axios.create({
    // 환경 변수에서 가져오며, 없을 경우를 대비한 기본값 설정
    baseURL: process.env.REACT_APP_API_URL || '/api',
    headers: {
        'Content-Type': 'application/json',
    },
    // 쿠키 기반 인증(HttpOnly)을 사용할 경우 필수 설정
    withCredentials: true, 
    // 요청 타임아웃 설정 (DoS 공격 방어 및 사용자 경험 개선)
    timeout: 10000, 
});

// 2. 요청 인터셉터: 보안 강화
api.interceptors.request.use(
    (config) => {
        const token = localStorage.getItem('accessToken');
        
        // 토큰이 존재할 때만 Authorization 헤더 설정
        if (token) {
            // 주의: localStorage는 XSS에 취약하므로 중요 서비스는 HttpOnly 쿠키 방식을 권장합니다.
            config.headers.Authorization = `Bearer ${token}`;
        }

        // 추가 보안: 모든 POST/PUT/DELETE 요청에 커스텀 헤더를 넣어 단순 CSRF 방어
        if (['post', 'put', 'delete', 'patch'].includes(config.method)) {
            config.headers['X-Requested-With'] = 'XMLHttpRequest';
        }
        
        return config;
    },
    (error) => {
        console.error('[Request Error]', error); // 운영 환경에서는 로그 라이브러리 사용 권장
        return Promise.reject(error);
    }
);

// 3. 응답 인터셉터: 세밀한 에러 제어
api.interceptors.response.use(
    (response) => response,
    async (error) => {
        const originalRequest = error.config;

        // 401 에러(인증 만료) 처리
        if (error.response && error.response.status === 401) {
            // 무한 루프 방지: 이미 토큰 갱신 시도를 한 경우라면 로그아웃
            if (originalRequest._retry) {
                handleLogout();
                return Promise.reject(error);
            }

            originalRequest._retry = true;

            /* 
               [추가 권장] 
               여기서 refreshToken을 이용해 새로운 accessToken을 받는 로직을 구현하면 
               사용자가 튕기지 않고 보안성을 높일 수 있습니다.
            */
            
            handleLogout();
        }

        // 403 에러(권한 없음) 처리: 관리자 페이지 등에 일반 유저 접근 시
        if (error.response && error.response.status === 403) {
            alert('해당 메뉴에 대한 접근 권한이 없습니다.');
        }

        // 500 에러 처리 (서버 내부 정보 노출 방지 대행)
        if (error.response && error.response.status >= 500) {
            console.error('Server Error. Please try again later.');
        }

        return Promise.reject(error);
    }
);

// 보안을 위한 공통 로그아웃 처리 함수
const handleLogout = () => {
    localStorage.removeItem('accessToken');
    localStorage.removeItem('refreshToken');
    // 사용 중인 도메인이 다를 경우를 대비해 절대 경로로 이동
    window.location.href = '/login';
};

export default api;
