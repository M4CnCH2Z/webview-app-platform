package com.project.shop.global.config.security;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.project.shop.global.error.ErrorCode;
import com.project.shop.global.error.exception.BusinessException;
import com.project.shop.member.controller.request.LoginRequest;
import com.project.shop.member.domain.Member;
import com.project.shop.member.repository.MemberRepository;
import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.util.Date;
import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Component
@RequiredArgsConstructor
public class TokenProvider {

    private static final String AUTHORITIES_KEY  = "auth";
    private static final String BEARER_TYPE = "Bearer";
    private static final String MEMBER_ID_CLAIM_KEY = "memberId";
    private static final long ACCESS_TOKEN_EXPIRE_TIME = 1000 * 60 * 30;             // 30분 (보안 강화)
    private static final long REFRESH_TOKEN_EXPIRE_TIME = 1000 * 60 * 60 * 24 * 7;  // 7일

    private final MemberRepository memberRepository;
    private final ObjectMapper objectMapper;
    private final RefreshTokenService refreshTokenService;

    private final SecretKey key = Keys.secretKeyFor(SignatureAlgorithm.HS256);

    public JwtTokenDto generateToken(LoginRequest loginRequest) throws JsonProcessingException {

        long nowTime = new Date().getTime();
        Member member = memberRepository.findByLoginId(loginRequest.getLoginId()).orElseThrow(
                () -> new BusinessException(ErrorCode.NOT_FOUND_MEMBER));
        List<String> roles = member.getRoles().stream().map(x -> x.getRoleType().toString()).toList();

        String data = objectMapper.writeValueAsString(roles);

        // Access Token 생성 (30분)
        Date accessTokenExpiresIn = new Date(nowTime + ACCESS_TOKEN_EXPIRE_TIME);
        String accessToken = Jwts.builder()
                .setSubject(loginRequest.getLoginId())              //"sub":"로그인ID"
                .claim(MEMBER_ID_CLAIM_KEY, member.getId())         //"memberId":"1"
                .claim(AUTHORITIES_KEY, data)                       //"auth": "[\"ROLE_USER\",\"ROLE_SELLER\"]"
                .claim("LOGIN_TYPE", member.getLoginType())         //"LOGIN_TYPE":"KAKAO"
                .setExpiration(accessTokenExpiresIn)                //"exp":"12345678"
                .signWith(key)
                .compact();

        // Refresh Token 생성 (7일)
        Date refreshTokenExpiresIn = new Date(nowTime + REFRESH_TOKEN_EXPIRE_TIME);
        String refreshToken = Jwts.builder()
                .setSubject(loginRequest.getLoginId())              // 로그인ID만 포함 (최소 정보)
                .setExpiration(refreshTokenExpiresIn)
                .signWith(key)
                .compact();

        // Redis에 Refresh Token 저장
        refreshTokenService.saveRefreshToken(loginRequest.getLoginId(), refreshToken);

        return JwtTokenDto.builder()
                .grantType(BEARER_TYPE)
                .accessToken(accessToken)
                .refreshToken(refreshToken)
                .accessTokenExpiresIn(accessTokenExpiresIn.getTime())
                .refreshTokenExpiresIn(refreshTokenExpiresIn.getTime())
                .build();
    }

    //JWT 토큰을 복호화해서 토큰에 들어있는 정보를 꺼내는 메서드
    public Authentication getAuthentication(String accessToken) throws JsonProcessingException {
        //토큰 복호화
        Claims claims = parseClaims(accessToken);

        if (claims.get(AUTHORITIES_KEY) == null) { // "auth"
            throw new RuntimeException("권한 정보가 없는 토큰입니다.");
        }

        // 클레임에서 권한 정보 가져오기
        List<String> data = objectMapper.readValue(claims.get(AUTHORITIES_KEY).toString(), List.class) ;
        List<SimpleGrantedAuthority> authorities = data
                .stream().map(role -> new SimpleGrantedAuthority(role))
                .collect(Collectors.toList());

        // UserDetails 객체를 만들어서 Authentication 리턴
        UserDetails principal = new User(claims.getSubject(), "", authorities);
        return new UsernamePasswordAuthenticationToken(principal, "", authorities);

    }

    // 토큰정보를 검증하는 메서드
    public boolean validateToken(String token) {
        try {
             Jwts.parser().verifyWith(key).build().parseSignedClaims(token);
            return true;
        } catch (io.jsonwebtoken.security.SecurityException | MalformedJwtException e) {
            log.info("잘못된 JWT 서명입니다.");
        } catch (ExpiredJwtException e) {
            log.info("만료된 JWT 토큰입니다. ");
        } catch (UnsupportedJwtException e) {
            log.info("지원되지 않는 JWT 토큰입니다.");
        } catch (IllegalStateException e) {
            log.info("JWT 토큰이 잘못되었습니다.");
        }
        return false;
    }

    // 복호화 메서드 따로 생성
    private Claims parseClaims(String token) {
        try {
             return Jwts.parser().verifyWith(key).build().parseSignedClaims(token).getPayload();
            } catch (ExpiredJwtException e) {
            return e.getClaims();
        }
    }

    /**
     * Refresh Token을 사용하여 새로운 Access Token + Refresh Token 발급
     *
     * Sliding Session 적용:
     * - Refresh Token 재발급 시 TTL 연장
     * - 활성 사용자는 자동으로 세션 유지
     *
     * Refresh Token Rotation:
     * - 새로운 Refresh Token 발급
     * - 기존 Refresh Token은 Redis에서 자동 교체
     *
     * @param refreshToken 클라이언트가 보낸 Refresh Token
     * @return 새로운 Access Token + Refresh Token
     */
    public JwtTokenDto reissueToken(String refreshToken) throws JsonProcessingException {
        // 1. Refresh Token 유효성 검증
        if (!validateToken(refreshToken)) {
            throw new BusinessException(ErrorCode.INVALID_REFRESH_TOKEN);
        }

        // 2. Refresh Token에서 loginId 추출
        Claims claims = parseClaims(refreshToken);
        String loginId = claims.getSubject();

        if (loginId == null) {
            throw new BusinessException(ErrorCode.INVALID_REFRESH_TOKEN);
        }

        // 3. Redis에서 저장된 Refresh Token 조회
        String storedRefreshToken = refreshTokenService.getRefreshToken(loginId);

        if (storedRefreshToken == null) {
            // Redis에서 만료되었거나 로그아웃됨
            throw new BusinessException(ErrorCode.EXPIRED_REFRESH_TOKEN);
        }

        // 4. Refresh Token 일치 여부 확인 (Reuse Detection)
        if (!refreshToken.equals(storedRefreshToken)) {
            // 이미 사용된 Refresh Token으로 재발급 시도 → 탈취 의심
            log.warn("🚨 Refresh Token reuse detected for loginId: {}", loginId);
            refreshTokenService.deleteRefreshToken(loginId); // 모든 세션 무효화
            throw new BusinessException(ErrorCode.REFRESH_TOKEN_REUSE_DETECTED);
        }

        // 5. 회원 정보 조회
        Member member = memberRepository.findByLoginId(loginId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND_MEMBER));

        // 6. 새로운 토큰 발급 (Rotation)
        long nowTime = new Date().getTime();
        List<String> roles = member.getRoles().stream()
                .map(x -> x.getRoleType().toString())
                .toList();
        String data = objectMapper.writeValueAsString(roles);

        // 6-1. 새 Access Token 생성
        Date accessTokenExpiresIn = new Date(nowTime + ACCESS_TOKEN_EXPIRE_TIME);
        String newAccessToken = Jwts.builder()
                .setSubject(loginId)
                .claim(MEMBER_ID_CLAIM_KEY, member.getId())
                .claim(AUTHORITIES_KEY, data)
                .claim("LOGIN_TYPE", member.getLoginType())
                .setExpiration(accessTokenExpiresIn)
                .signWith(key)
                .compact();

        // 6-2. 새 Refresh Token 생성 (Rotation)
        Date refreshTokenExpiresIn = new Date(nowTime + REFRESH_TOKEN_EXPIRE_TIME);
        String newRefreshToken = Jwts.builder()
                .setSubject(loginId)
                .setExpiration(refreshTokenExpiresIn)
                .signWith(key)
                .compact();

        // 7. Redis에 새 Refresh Token 저장 (기존 것 자동 교체 + TTL 연장)
        refreshTokenService.saveRefreshToken(loginId, newRefreshToken);

        log.info("🔄 Token reissued for loginId: {}", loginId);

        return JwtTokenDto.builder()
                .grantType(BEARER_TYPE)
                .accessToken(newAccessToken)
                .refreshToken(newRefreshToken)
                .accessTokenExpiresIn(accessTokenExpiresIn.getTime())
                .refreshTokenExpiresIn(refreshTokenExpiresIn.getTime())
                .build();
    }

    /**
     * JWT 토큰에서 loginId 추출
     *
     * @param token JWT 토큰
     * @return loginId
     */
    public String getLoginIdFromToken(String token) {
        Claims claims = parseClaims(token);
        return claims.getSubject();
    }
}
