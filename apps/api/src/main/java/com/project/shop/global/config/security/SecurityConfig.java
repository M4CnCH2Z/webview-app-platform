package com.project.shop.global.config.security;

import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.header.writers.XXssProtectionHeaderWriter;
import org.springframework.web.cors.CorsConfigurationSource;

@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
// 2025년 기준: EnableGlobalMethodSecurity 대신 EnableMethodSecurity 사용 권장
@EnableMethodSecurity 
public class SecurityConfig {

    private final TokenProvider tokenProvider;
    private final JwtAuthenticationEntryPoint jwtAuthenticationEntryPoint;
    private final JwtAccessDeniedHandler jwtAccessDeniedHandler;
    private final CorsConfigurationSource corsConfigurationSource;

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            // 1. CORS 설정: DELETE, OPTIONS 메서드 지원을 포함한 Source 연결
            .cors(cors -> cors.configurationSource(corsConfigurationSource))

            // 2. CSRF 비활성화: JWT Stateless 환경에 최적화
            .csrf(csrf -> csrf.disable())

            // 3. 세션 정책: Stateless (서버 세션 사용 안함)
            .sessionManagement(session -> 
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS)
            )

            // 4. 예외 처리: 인증 및 인가 실패 핸들러
            .exceptionHandling(exception -> exception
                .authenticationEntryPoint(jwtAuthenticationEntryPoint)
                .accessDeniedHandler(jwtAccessDeniedHandler)
            )

            // 5. 불필요한 로그인 방식 비활성화
            .formLogin(form -> form.disable())
            .httpBasic(httpBasic -> httpBasic.disable())

            // 6. 보안 헤더 설정 강화
            .headers(headers -> headers
                // [클릭재킹 방어] H2 콘솔 접근을 위해 sameOrigin 유지, 배포 시 deny() 권장
                .frameOptions(frame -> frame.sameOrigin()) 
                
                // [XSS 방어] 브라우저 기본 필터 차단 모드 활성화
                .xssProtection(xss -> xss
                    .headerValue(XXssProtectionHeaderWriter.HeaderValue.ENABLED_MODE_BLOCK)
                )

                // [CSP 보안 정책] 주석을 제거하고 이미지/통신 허용 도메인을 명확히 지정
                // localhost와 IP 주소를 모두 허용하여 CORS preflight 이후 차단 방지
                .contentSecurityPolicy(csp -> csp
                    .policyDirectives("default-src 'self'; " +
                                     "script-src 'self' 'unsafe-inline'; " +
                                     "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com; " +
                                     "img-src 'self' data: blob: http://192.168.10.55:8080 http://localhost:8080; " +
                                     "connect-src 'self' http://192.168.10.55:8080 http://localhost:8080; " +
                                     "font-src 'self' https://cdnjs.cloudflare.com; " +
                                     "frame-ancestors 'none';")
                )
            )

            // 7. 요청 권한 상세 설정
            .authorizeHttpRequests(auth -> auth
                // OPTIONS 메서드(Preflight)는 보안 검사 전 무조건 허용하여 CORS 에러 방지
                .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                
                // 정적 리소스 및 H2 콘솔 허용
                .requestMatchers("/h2-console/**", "/uploads/**").permitAll()
                
                // 공개 API (회원가입, 로그인, 상품 조회 등)
                .requestMatchers("/api/members/signup", "/api/members/exist", "/api/members/login").permitAll()
                .requestMatchers("/api/goods", "/api/goods/**", "/api/categories", "/api/categories/**").permitAll()
                .requestMatchers("/api/redis/test/**").permitAll()
                .requestMatchers("/actuator/health", "/actuator/prometheus").permitAll()
                .requestMatchers(PERMIT_URL_ARRAY).permitAll()
                
                // 그 외 모든 요청은 인증 필요
                .anyRequest().authenticated()
            )

            // 8. JWT 전용 보안 설정 적용
            .with(new JwtSecurityConfig(tokenProvider), customizer -> {});

        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        // 2025년 기준 권장 암호화 알고리즘
        return new BCryptPasswordEncoder();
    }

    private static final String[] PERMIT_URL_ARRAY = {
            "/v2/api-docs", "/swagger-resources", "/swagger-resources/**",
            "/configuration/ui", "/configuration/security", "/swagger-ui.html",
            "/webjars/**", "/v3/api-docs/**", "/swagger-ui/**"
    };
}
