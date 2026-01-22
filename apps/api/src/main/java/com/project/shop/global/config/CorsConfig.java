package com.project.shop.global.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;

@Configuration
public class CorsConfig {

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();

        // React 개발 서버 포트 허용
        
         configuration.setAllowedOrigins(Arrays.asList(
        "http://localhost:3000",       // 로컬 테스트용
        "http://localhost:3001",       // 로컬 테스트용 (포트 변경)
        "http://192.168.10.55:3000",    // 가상머신 IP를 통한 접속 허용 (본인의 VM IP 입력)
        "http://192.168.10.55:3001",    // 가상머신 IP를 통한 접속 허용 (포트 변경)
        "http://127.0.0.1:3000",       // 루프백 주소 추가
        "http://127.0.0.1:3001",       // 루프백 주소 추가 (포트 변경)
        "https://m4cnch2z.site",
        "https://www.m4cnch2z.site",
        "https://test.m4cnch2z.site",
        "https://www.test.m4cnch2z.site"
          ));


        // [중요] DELETE 메서드와 OPTIONS 메서드 반드시 포함
    configuration.setAllowedMethods(Arrays.asList("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
    
    // [중요] Authorization 헤더 허용
    configuration.setAllowedHeaders(Arrays.asList("Authorization", "Content-Type", "Cache-Control", "x-requested-with" ));
    

        // 인증 정보 허용 (쿠키, Authorization 헤더 등)
        configuration.setAllowCredentials(true);

        // 노출할 헤더 설정
        configuration.setExposedHeaders(Arrays.asList("Authorization"));

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);

        return source;
    }
}
