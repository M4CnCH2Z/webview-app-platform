# RabbitMQ 메시지 큐 시스템 가이드

> 이 문서는 쇼핑몰 프로젝트에서 RabbitMQ를 사용한 비동기 메시지 처리 시스템에 대한 상세 가이드입니다.

**작성일**: 2025.11.16
**RabbitMQ 버전**: 3.12-management
**Spring AMQP 버전**: 2.4.8

---

## 📋 목차

1. [RabbitMQ 개요](#rabbitmq-개요)
2. [왜 RabbitMQ를 사용하는가?](#왜-rabbitmq를-사용하는가)
3. [시스템 아키텍처](#시스템-아키텍처)
4. [환경 설정](#환경-설정)
5. [코드 구조](#코드-구조)
6. [메시지 플로우](#메시지-플로우)
7. [트러블슈팅](#트러블슈팅)
8. [모니터링](#모니터링)
9. [확장 가능성](#확장-가능성)
10. [참고 자료](#참고-자료)

---

## RabbitMQ 개요

### RabbitMQ란?

RabbitMQ는 **AMQP(Advanced Message Queuing Protocol)** 기반의 오픈소스 메시지 브로커입니다.

**핵심 개념:**
- **Producer (발행자)**: 메시지를 생성하고 전송하는 주체
- **Queue (큐)**: 메시지를 저장하는 버퍼
- **Consumer (소비자)**: 메시지를 수신하고 처리하는 주체
- **Exchange (교환기)**: 메시지를 적절한 큐로 라우팅하는 역할
- **Routing Key**: 메시지를 라우팅할 때 사용하는 키

### 주요 특징

1. **비동기 처리**: 요청과 응답을 분리하여 성능 향상
2. **느슨한 결합 (Loose Coupling)**: 서비스 간 직접 의존성 제거
3. **확장성**: 큐를 통해 부하 분산 가능
4. **신뢰성**: 메시지 영속화 및 ACK 메커니즘
5. **다양한 라우팅**: Direct, Topic, Fanout, Headers Exchange 지원

---

## 왜 RabbitMQ를 사용하는가?

### 프로젝트에서의 활용 목적

#### 1. 주문 생성 시 알림 발송 (비동기 처리)

**문제 상황:**
```
사용자 → 주문 생성 요청
   ↓
서버: 주문 DB 저장 (필수)
서버: 이메일 발송 (부가 기능)  ← 시간 소요
서버: 카카오톡 알림 (부가 기능) ← 시간 소요
서버: 관리자 알림 (부가 기능)  ← 시간 소요
   ↓
사용자 ← 응답 (느림! 😢)
```

**RabbitMQ 적용 후:**
```
사용자 → 주문 생성 요청
   ↓
서버: 주문 DB 저장
서버: RabbitMQ 이벤트 발행 (빠름!)
   ↓
사용자 ← 즉시 응답 (빠름! 😊)

[별도 프로세스]
RabbitMQ Consumer → 이메일 발송
                 → 카카오톡 알림
                 → 관리자 알림
```

#### 2. 트래픽 급증 대응

**블랙프라이데이 시나리오:**
- 평소: 초당 10건 주문
- 이벤트: 초당 1000건 주문 (100배 증가!)

**RabbitMQ 없이:**
```
서버 ━━━ 동시 처리 한계 초과 ━━━ 서버 다운 💥
```

**RabbitMQ 사용:**
```
주문 요청 → Queue에 쌓임 → Consumer가 처리 가능한 속도로 소비
서버 안정적 유지 ✅
```

#### 3. 서비스 분리 (MSA 준비)

**모놀리식 (현재):**
```
[쇼핑몰 서버]
├─ 주문 서비스
├─ 알림 서비스 ← 주문 서비스에 의존
└─ 결제 서비스
```

**MSA (미래):**
```
[주문 서비스] ━━→ [RabbitMQ] ━━→ [알림 서비스 (독립)]
                            ━━→ [데이터 분석 서비스 (신규)]
                            ━━→ [재고 서비스 (독립)]
```

---

## 시스템 아키텍처

### 전체 구조도

```
┌─────────────────────────────────────────────────────────────────┐
│                         Shopping Mall                            │
│                                                                   │
│  ┌─────────────┐                                                 │
│  │   OrderAPI  │                                                 │
│  │  Controller │                                                 │
│  └──────┬──────┘                                                 │
│         │                                                         │
│         ▼                                                         │
│  ┌─────────────┐      ┌──────────────────┐                      │
│  │   Order     │      │ OrderEvent       │                      │
│  │   Service   │─────→│ Publisher        │                      │
│  └─────────────┘      └────────┬─────────┘                      │
│         │                      │                                 │
│         │ DB 저장               │ 메시지 발행                      │
│         ▼                      ▼                                 │
│  ┌─────────────┐      ┌──────────────────┐                      │
│  │   MySQL     │      │   RabbitMQ       │                      │
│  │   Order     │      │                  │                      │
│  │   Table     │      │  ┌────────────┐  │                      │
│  └─────────────┘      │  │   Queue    │  │                      │
│                       │  │  order.    │  │                      │
│                       │  │notification│  │                      │
│                       │  └──────┬─────┘  │                      │
│                       └─────────┼────────┘                      │
│                                 │                                │
│                                 ▼                                │
│                       ┌──────────────────┐                      │
│                       │ OrderNotification│                      │
│                       │    Consumer      │                      │
│                       └────────┬─────────┘                      │
│                                │                                │
│              ┌─────────────────┼─────────────────┐              │
│              ▼                 ▼                 ▼              │
│      ┌──────────────┐  ┌──────────────┐ ┌──────────────┐      │
│      │    Email     │  │   KakaoTalk  │ │    Admin     │      │
│      │   Service    │  │   Service    │ │   Alert      │      │
│      └──────────────┘  └──────────────┘ └──────────────┘      │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### RabbitMQ 내부 구조

```
┌─────────────────────────────────────────────────────────┐
│                      RabbitMQ Broker                     │
│                                                           │
│  ┌────────────┐                                          │
│  │  Producer  │                                          │
│  │ (Publisher)│                                          │
│  └─────┬──────┘                                          │
│        │                                                  │
│        │ publishOrderCreated()                           │
│        │ + OrderCreatedEvent                             │
│        ▼                                                  │
│  ┌───────────────────────────────────────┐               │
│  │        Direct Exchange                │               │
│  │      "order.exchange"                 │               │
│  │                                       │               │
│  │  Routing Key: "order.notification"   │               │
│  └───────────────┬───────────────────────┘               │
│                  │                                        │
│                  │ 라우팅                                  │
│                  ▼                                        │
│  ┌───────────────────────────────────────┐               │
│  │            Queue                      │               │
│  │  "order.notification.queue"          │               │
│  │                                       │               │
│  │  - durable: true (영속화)             │               │
│  │  - message TTL: 무제한                │               │
│  │  - max length: 무제한                 │               │
│  └───────────────┬───────────────────────┘               │
│                  │                                        │
│                  │ consume                                │
│                  ▼                                        │
│  ┌────────────────────────────────────────┐              │
│  │         Consumer                       │              │
│  │  @RabbitListener                       │              │
│  │  "order.notification.queue"           │              │
│  └────────────────────────────────────────┘              │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

---

## 환경 설정

### 활성화/비활성화 플래그

RabbitMQ 사용 여부는 아래 플래그로 제어합니다.

- 설정 키: `app.rabbit.enabled`
- 환경 변수: `APP_RABBIT_ENABLED`

예시 (RabbitMQ 비활성화):

```yaml
app:
  rabbit:
    enabled: false
```

### 1. Docker Compose 설정

**파일 위치**: `docker-compose.yml`

```yaml
services:
  rabbitmq:
    image: rabbitmq:3.12-management
    container_name: shoppingmall-rabbitmq
    ports:
      - "5672:5672"    # AMQP 프로토콜 포트
      - "15672:15672"  # 관리 웹 UI 포트
    environment:
      RABBITMQ_DEFAULT_USER: admin
      RABBITMQ_DEFAULT_PASS: admin1234
      TZ: Asia/Seoul
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    networks:
      - shop-network

volumes:
  rabbitmq_data:

networks:
  shop-network:
    driver: bridge
```

**포트 설명:**
- `5672`: 애플리케이션이 메시지를 발행/소비하는 포트
- `15672`: 웹 브라우저로 RabbitMQ 관리 UI 접속 포트

**실행 명령어:**
```bash
# RabbitMQ 시작
docker-compose up -d rabbitmq

# 로그 확인
docker logs -f shoppingmall-rabbitmq

# 상태 확인
docker ps | grep rabbitmq
```

**관리 UI 접속:**
- URL: http://localhost:15672
- Username: `admin`
- Password: `admin1234`

---

### 2. Spring Boot 의존성

**파일 위치**: `build.gradle`

```gradle
dependencies {
    // RabbitMQ
    implementation 'org.springframework.boot:spring-boot-starter-amqp'

    // Jackson (JSON 직렬화)
    implementation 'com.fasterxml.jackson.datatype:jackson-datatype-jsr310'
}
```

**의존성 설명:**
- `spring-boot-starter-amqp`: Spring AMQP 및 RabbitMQ 클라이언트 포함
- `jackson-datatype-jsr310`: LocalDateTime 등 Java 8 날짜/시간 API 직렬화 지원

---

### 3. Application 설정

**파일 위치**: `src/main/resources/application-local.yml`

```yaml
spring:
  rabbitmq:
    host: localhost
    port: 5672
    username: admin
    password: admin1234
    virtual-host: /

    # 연결 설정
    connection-timeout: 10000  # 10초
    requested-heartbeat: 60    # 60초마다 heartbeat

    # Publisher 설정
    publisher-confirm-type: correlated  # 메시지 발행 확인
    publisher-returns: true             # 라우팅 실패 시 반환

    # Consumer 설정 (선택)
    listener:
      simple:
        acknowledge-mode: auto         # 자동 ACK
        retry:
          enabled: true
          initial-interval: 1000       # 1초 후 재시도
          max-attempts: 3              # 최대 3번 재시도
          multiplier: 2.0              # 재시도 간격 2배씩 증가
```

**설정 설명:**

| 설정 | 설명 | 값 |
|------|------|-----|
| `host` | RabbitMQ 서버 주소 | localhost |
| `port` | AMQP 포트 | 5672 |
| `username` | 인증 사용자명 | admin |
| `password` | 인증 비밀번호 | admin1234 |
| `virtual-host` | 가상 호스트 (네임스페이스) | / (기본값) |
| `publisher-confirm-type` | 발행 확인 타입 | correlated |
| `publisher-returns` | 라우팅 실패 메시지 반환 | true |
| `acknowledge-mode` | ACK 모드 | auto |

---

## 코드 구조

### 전체 파일 구조

```
src/main/java/com/project/shop/
├── order/
│   ├── event/
│   │   └── OrderCreatedEvent.java        # 이벤트 DTO
│   ├── publisher/
│   │   └── OrderEventPublisher.java      # 이벤트 발행자
│   ├── consumer/
│   │   └── OrderNotificationConsumer.java # 이벤트 소비자
│   └── service/
│       └── impl/
│           └── OrderServiceImpl.java     # 주문 서비스 (발행 트리거)
└── global/
    └── config/
        └── RabbitMQConfig.java           # RabbitMQ 설정
```

---

### 1. RabbitMQ 설정 클래스

**파일 위치**: `src/main/java/com/project/shop/global/config/RabbitMQConfig.java`

```java
@Configuration
public class RabbitMQConfig {

    // ========== 상수 정의 ==========

    public static final String ORDER_NOTIFICATION_QUEUE = "order.notification.queue";
    public static final String ORDER_EXCHANGE = "order.exchange";
    public static final String ORDER_NOTIFICATION_ROUTING_KEY = "order.notification";

    // ========== Bean 정의 ==========

    /**
     * 1. Queue 생성
     *
     * durable = true: 서버 재시작 시에도 큐 유지
     */
    @Bean
    public Queue orderNotificationQueue() {
        return new Queue(ORDER_NOTIFICATION_QUEUE, true);
    }

    /**
     * 2. Exchange 생성
     *
     * DirectExchange: Routing Key가 정확히 일치하는 Queue로만 메시지 전달
     */
    @Bean
    public DirectExchange orderExchange() {
        return new DirectExchange(ORDER_EXCHANGE);
    }

    /**
     * 3. Binding (Queue ↔ Exchange 연결)
     *
     * orderNotificationQueue를 orderExchange에 바인딩
     * Routing Key: "order.notification"
     */
    @Bean
    public Binding orderNotificationBinding(
            Queue orderNotificationQueue,
            DirectExchange orderExchange) {
        return BindingBuilder
                .bind(orderNotificationQueue)
                .to(orderExchange)
                .with(ORDER_NOTIFICATION_ROUTING_KEY);
    }

    /**
     * 4. 메시지 컨버터 설정
     *
     * Jackson2JsonMessageConverter를 사용하여 객체 <-> JSON 자동 변환
     * LocalDateTime 등 Java 8 날짜/시간 API 지원을 위해 JavaTimeModule 추가
     */
    @Bean
    public MessageConverter messageConverter() {
        ObjectMapper objectMapper = new ObjectMapper();

        // Java 8 날짜/시간 API 지원
        objectMapper.registerModule(new JavaTimeModule());

        // 날짜를 타임스탬프가 아닌 ISO-8601 문자열로 직렬화
        objectMapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

        return new Jackson2JsonMessageConverter(objectMapper);
    }

    /**
     * 5. RabbitTemplate 설정
     *
     * 메시지를 발행할 때 사용하는 템플릿
     * JSON 컨버터를 설정하여 객체를 자동으로 JSON으로 변환
     */
    @Bean
    public RabbitTemplate rabbitTemplate(
            ConnectionFactory connectionFactory,
            MessageConverter messageConverter) {
        RabbitTemplate rabbitTemplate = new RabbitTemplate(connectionFactory);
        rabbitTemplate.setMessageConverter(messageConverter);
        return rabbitTemplate;
    }
}
```

**주요 개념 설명:**

#### Exchange 타입 비교

| 타입 | 설명 | 사용 사례 |
|------|------|----------|
| **Direct** | Routing Key가 정확히 일치 | 단일 큐 라우팅 (현재 사용) |
| **Topic** | Routing Key 패턴 매칭 | 다중 큐 필터링 (order.*, *.critical) |
| **Fanout** | 모든 큐에 브로드캐스트 | 전체 알림 발송 |
| **Headers** | 헤더 속성으로 라우팅 | 복잡한 라우팅 조건 |

#### Durable vs Non-Durable

```java
// Durable Queue (영속화)
new Queue("order.queue", true);
→ RabbitMQ 재시작 후에도 큐 유지
→ 메시지 영속화 (delivery mode = 2 설정 시)

// Non-Durable Queue
new Queue("temp.queue", false);
→ RabbitMQ 재시작 시 큐 삭제
→ 임시 큐로 사용
```

---

### 2. 이벤트 DTO 클래스

**파일 위치**: `src/main/java/com/project/shop/order/event/OrderCreatedEvent.java`

```java
/**
 * 주문 생성 이벤트 DTO
 *
 * RabbitMQ를 통해 전달되는 주문 생성 이벤트 정보
 * Serializable을 구현하여 직렬화 가능하도록 설정
 */
@Getter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class OrderCreatedEvent implements Serializable {

    private static final long serialVersionUID = 1L;

    /**
     * 주문 ID
     */
    private Long orderId;

    /**
     * 주문번호 (UUID 문자열)
     */
    private String merchantId;

    /**
     * 회원 ID
     */
    private Long memberId;

    /**
     * 회원 로그인 ID
     */
    private String memberLoginId;

    /**
     * 회원 이메일
     */
    private String memberEmail;

    /**
     * 총 주문 금액
     */
    private Integer totalPrice;

    /**
     * 주문 상태
     */
    private String orderStatus;

    /**
     * 주문 생성 시간
     */
    private LocalDateTime createdAt;

    /**
     * 이벤트 발생 시간
     */
    @Builder.Default
    private LocalDateTime eventTime = LocalDateTime.now();
}
```

**설계 포인트:**

1. **Serializable 구현**: RabbitMQ 메시지로 전송하기 위해 직렬화 필요
2. **serialVersionUID**: 클래스 버전 관리 (역직렬화 호환성)
3. **@Builder**: 빌더 패턴으로 객체 생성 (가독성 향상)
4. **@Builder.Default**: eventTime 기본값 설정 (현재 시간)

**왜 모든 필드를 포함하는가?**
- 이벤트는 **자기완결적(Self-Contained)**이어야 함
- Consumer가 DB 조회 없이 필요한 모든 정보를 가져야 함
- 주문 데이터 삭제되어도 이벤트 처리 가능

---

### 3. 이벤트 발행자 (Publisher)

**파일 위치**: `src/main/java/com/project/shop/order/publisher/OrderEventPublisher.java`

```java
/**
 * 주문 이벤트 발행자
 *
 * 주문 관련 이벤트를 RabbitMQ에 발행하는 클래스
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class OrderEventPublisher {

    private final RabbitTemplate rabbitTemplate;

    /**
     * 주문 생성 이벤트 발행
     *
     * @param event 주문 생성 이벤트 DTO
     */
    public void publishOrderCreated(OrderCreatedEvent event) {
        try {
            log.info("[RabbitMQ] 주문 생성 이벤트 발행 시작: orderId={}, merchantId={}",
                    event.getOrderId(), event.getMerchantId());

            // RabbitMQ에 메시지 발행
            rabbitTemplate.convertAndSend(
                RabbitMQConfig.ORDER_EXCHANGE,              // Exchange 이름
                RabbitMQConfig.ORDER_NOTIFICATION_ROUTING_KEY, // Routing Key
                event                                        // 메시지 본문 (DTO)
            );

            log.info("[RabbitMQ] 주문 생성 이벤트 발행 성공: orderId={}", event.getOrderId());

        } catch (Exception e) {
            log.error("[RabbitMQ] 주문 생성 이벤트 발행 실패: orderId={}, error={}",
                    event.getOrderId(), e.getMessage(), e);

            // 발행 실패 시 처리 로직 (선택)
            // 1. DB에 실패 로그 저장
            // 2. 재시도 로직 추가
            // 3. 알림 발송 (Slack, Email 등)
        }
    }
}
```

**convertAndSend() 메서드 설명:**

```java
rabbitTemplate.convertAndSend(
    exchange,      // 메시지를 보낼 Exchange 이름
    routingKey,    // 라우팅 키 (Queue와 바인딩된 키)
    message        // 메시지 객체 (자동으로 JSON 변환)
);
```

**메시지 변환 과정:**

```
OrderCreatedEvent 객체
    ↓
MessageConverter (Jackson2Json)
    ↓
JSON 문자열
    ↓
RabbitMQ 메시지
    ↓
Queue에 저장
```

**에러 처리 전략:**

| 시나리오 | 처리 방법 |
|---------|----------|
| RabbitMQ 연결 실패 | 로그 기록 + DB에 실패 이벤트 저장 (나중에 재발행) |
| JSON 직렬화 실패 | 로그 기록 + 개발자 알림 (코드 수정 필요) |
| Exchange 없음 | 로그 기록 + 자동 생성 or 배포 롤백 |

---

### 4. 이벤트 소비자 (Consumer)

**파일 위치**: `src/main/java/com/project/shop/order/consumer/OrderNotificationConsumer.java`

```java
/**
 * 주문 알림 Consumer
 *
 * RabbitMQ의 order.notification.queue에서 메시지를 수신하여 처리
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class OrderNotificationConsumer {

    /**
     * 주문 생성 이벤트 수신 및 처리
     *
     * @param event 주문 생성 이벤트 DTO
     */
    @RabbitListener(queues = RabbitMQConfig.ORDER_NOTIFICATION_QUEUE)
    public void handleOrderCreated(OrderCreatedEvent event) {
        try {
            log.info("========================================");
            log.info("[RabbitMQ Consumer] 주문 생성 이벤트 수신 시작");
            log.info("주문 ID: {}", event.getOrderId());
            log.info("주문번호: {}", event.getMerchantId());
            log.info("회원 ID: {} ({})", event.getMemberId(), event.getMemberLoginId());
            log.info("회원 이메일: {}", event.getMemberEmail());
            log.info("총 금액: {}원", event.getTotalPrice());
            log.info("주문 상태: {}", event.getOrderStatus());
            log.info("주문 생성 시간: {}", event.getCreatedAt());
            log.info("이벤트 발생 시간: {}", event.getEventTime());
            log.info("========================================");

            // 1. 이메일 알림 발송
            sendEmailNotification(event);

            // 2. 카카오톡 알림 발송
            sendKakaoNotification(event);

            // 3. 관리자 대시보드 알림
            sendAdminNotification(event);

            log.info("[RabbitMQ Consumer] 주문 생성 이벤트 처리 완료: orderId={}",
                    event.getOrderId());

        } catch (Exception e) {
            log.error("[RabbitMQ Consumer] 주문 생성 이벤트 처리 실패: orderId={}, error={}",
                    event.getOrderId(), e.getMessage(), e);

            // 에러 처리 로직
            // 1. DB에 실패 로그 저장
            // 2. Dead Letter Queue로 이동
            // 3. 재시도 로직 (Spring AMQP의 RetryTemplate 사용)
            throw e; // 재시도를 위해 예외 던짐
        }
    }

    /**
     * 이메일 알림 발송 (Placeholder)
     */
    private void sendEmailNotification(OrderCreatedEvent event) {
        log.info("[Email] 주문 확인 이메일 발송: {}", event.getMemberEmail());

        // 실제 구현 예시:
        // emailService.sendOrderConfirmation(
        //     event.getMemberEmail(),
        //     event.getOrderId(),
        //     event.getTotalPrice()
        // );
    }

    /**
     * 카카오톡 알림 발송 (Placeholder)
     */
    private void sendKakaoNotification(OrderCreatedEvent event) {
        log.info("[KakaoTalk] 주문 확인 알림톡 발송: {}", event.getMemberLoginId());

        // 실제 구현 예시:
        // kakaoService.sendAlimtalk(
        //     event.getMemberId(),
        //     "주문이 완료되었습니다. 주문번호: " + event.getMerchantId()
        // );
    }

    /**
     * 관리자 알림 (Placeholder)
     */
    private void sendAdminNotification(OrderCreatedEvent event) {
        log.info("[Admin] 신규 주문 알림: orderId={}, amount={}원",
                event.getOrderId(), event.getTotalPrice());

        // 실제 구현 예시:
        // adminService.notifyNewOrder(event);
        // slackService.sendToChannel("#orders", "신규 주문: " + event.getMerchantId());
    }
}
```

**@RabbitListener 상세 설명:**

```java
@RabbitListener(
    queues = "order.notification.queue",  // 수신할 큐 이름
    concurrency = "1-3",                  // 동시 처리 스레드 수 (최소-최대)
    ackMode = "AUTO"                      // ACK 모드 (AUTO, MANUAL, NONE)
)
```

**Concurrency (동시성) 설정:**

```java
// 단일 스레드
concurrency = "1"

// 동적 스케일링 (부하에 따라 1~10개 스레드)
concurrency = "1-10"

// 고정 3개 스레드
concurrency = "3"
```

**ACK 모드 비교:**

| 모드 | 설명 | 장점 | 단점 |
|------|------|------|------|
| **AUTO** | Spring이 자동으로 ACK 전송 | 편리함 | 세밀한 제어 불가 |
| **MANUAL** | 개발자가 직접 ACK/NACK 전송 | 세밀한 제어 가능 | 코드 복잡도 증가 |
| **NONE** | ACK 없이 즉시 제거 | 빠름 | 메시지 유실 위험 |

---

### 5. 주문 서비스 (발행 트리거)

**파일 위치**: `src/main/java/com/project/shop/order/service/impl/OrderServiceImpl.java`

```java
@Service
@RequiredArgsConstructor
@Transactional
public class OrderServiceImpl implements OrderService {

    private final OrderEventPublisher orderEventPublisher;
    // ... 기타 의존성 생략

    @Override
    public void cartOrder(OrderCreateRequest orderCreateRequest) {
        Member member = getMember();
        String orderNumber = generateOrderNumber();

        // 1. 주문 생성
        Order order = Order.builder()
                .memberId(member.getId())
                .name(orderCreateRequest.getName())
                .phone(orderCreateRequest.getPhone())
                .zipcode(orderCreateRequest.getZipcode())
                .detailAddress(orderCreateRequest.getDetailAddress())
                .requirement(orderCreateRequest.getRequirement())
                .totalPrice(orderCreateRequest.getTotalPrice())
                .impUid(orderCreateRequest.getImpUid())
                .merchantId(orderCreateRequest.getMerchantId())
                .orderNumber(orderNumber)
                .build();

        // 2. 주문 아이템 생성 및 저장
        for (OrderCreateRequest.orderItemCreate orderItemCreate :
                orderCreateRequest.getOrderItemCreates()) {
            Goods goods = goodsRepository.findById(orderItemCreate.getGoodsId())
                    .orElseThrow(() -> new BusinessException(NOT_FOUND_GOODS));

            OrderItem orderItem = OrderItem.createOrderItem(
                    member, goods.getId(), orderItemCreate.getOrderPrice(),
                    orderItemCreate.getAmount(), order, goods.getGoodsName(),
                    orderItemCreate.getOrderPrice() / orderItemCreate.getAmount());
            orderItemRepository.save(orderItem);

            // Redis 장바구니에서 주문된 상품 삭제 (있는 경우만)
            Long optionNumber = orderItemCreate.getOptionNumber();
            try {
                redisCartService.removeFromCart(goods.getId(), optionNumber);
            } catch (BusinessException e) {
                if (!e.getErrorCode().equals(NOT_FOUND_CART)) {
                    throw e;
                }
            }
        }

        // 3. 주문 DB 저장
        orderRepository.save(order);

        // 4. 결제 DB 저장
        Pay pay = Pay.builder()
                .cardCompany(orderCreateRequest.getCardCompany())
                .cardNumber(orderCreateRequest.getCardNumber())
                .order(order)
                .payPrice(order.getTotalPrice())
                .build();
        payRepository.save(pay);

        // ========== 5. RabbitMQ 이벤트 발행 ==========
        OrderCreatedEvent event = OrderCreatedEvent.builder()
                .orderId(order.getId())
                .merchantId(order.getMerchantId())
                .memberId(member.getId())
                .memberLoginId(member.getLoginId())
                .memberEmail(member.getEmail())
                .totalPrice(order.getTotalPrice())
                .orderStatus(order.getOrderStatus().name())
                .createdAt(order.getCratedAt())
                .build();

        orderEventPublisher.publishOrderCreated(event);
        // ==========================================
    }
}
```

**트랜잭션과 메시지 발행 순서:**

```
┌─────────────────────────────────────┐
│  @Transactional 범위                 │
│                                      │
│  1. Order 생성                       │
│  2. OrderItem 생성                   │
│  3. Pay 생성                         │
│  4. DB 커밋                          │ ← 여기까지 성공해야 메시지 발행
└─────────────────────────────────────┘
         ↓
5. RabbitMQ 이벤트 발행 (트랜잭션 밖)
```

**왜 이 순서가 중요한가?**

❌ **나쁜 예 (메시지 먼저 발행):**
```
1. RabbitMQ 이벤트 발행 (성공)
2. Consumer가 이메일 발송 (성공)
3. DB 커밋 (실패!)
→ 고객은 이메일을 받았지만 주문이 없음! 😱
```

✅ **좋은 예 (DB 저장 후 발행):**
```
1. DB 커밋 (성공)
2. RabbitMQ 이벤트 발행 (성공)
→ 주문도 있고 이메일도 발송됨 ✅

만약 2번에서 실패하면?
→ 주문은 있지만 이메일 미발송 (나중에 재발행 가능)
```

---

## 메시지 플로우

### 전체 플로우 다이어그램

```
┌──────────┐                                                    ┌──────────┐
│  Client  │                                                    │ Consumer │
└────┬─────┘                                                    └────┬─────┘
     │                                                               │
     │ POST /api/orders                                              │
     │ ────────────────────────────────────────────────→             │
     │                                          ┌────────────────┐   │
     │                                          │ OrderService   │   │
     │                                          │                │   │
     │                                          │ 1. Order 저장  │   │
     │                                          │ 2. OrderItem   │   │
     │                                          │ 3. Pay 저장    │   │
     │                                          │ 4. DB 커밋     │   │
     │                                          └────────┬───────┘   │
     │                                                   │            │
     │                                          ┌────────▼───────┐   │
     │                                          │OrderEventPublisher
     │                                          │                │   │
     │                                          │ publishOrder   │   │
     │                                          │ Created()      │   │
     │                                          └────────┬───────┘   │
     │                                                   │            │
     │                                          ┌────────▼───────┐   │
     │                                          │ RabbitTemplate │   │
     │                                          │                │   │
     │                                          │convertAndSend()│   │
     │                                          └────────┬───────┘   │
     │                                                   │            │
     │                                          ┌────────▼───────────┐
     │                                          │    RabbitMQ        │
     │                                          │                    │
     │                                          │  order.exchange    │
     │                                          │         ↓          │
     │                                          │  order.notification│
     │                                          │      .queue        │
     │                                          └────────┬───────────┘
     │                                                   │            │
     │ ← 201 Created (즉시 응답!)                         │            │
     │ ←─────────────────────────────────────           │            │
     │                                                   │ @RabbitListener
     │                                                   │            │
     │                                                   └────────────▶
     │                                                    ┌───────────┐
     │                                                    │handleOrder│
     │                                                    │Created()  │
     │                                                    ├───────────┤
     │                                                    │1. Email   │
     │                                                    │2. Kakao   │
     │                                                    │3. Admin   │
     │                                                    └───────────┘
```

### 시간 흐름 (Timeline)

```
시간 →

0ms   : Client 주문 요청
10ms  : OrderService.cartOrder() 시작
15ms  : Order DB 저장
20ms  : OrderItem DB 저장
25ms  : Pay DB 저장
30ms  : DB 커밋 완료
35ms  : RabbitMQ 이벤트 발행
40ms  : Client에 응답 (201 Created) ✅ ← 여기서 사용자는 완료!

        [별도 스레드에서 비동기 처리]
45ms  : RabbitMQ에 메시지 저장
50ms  : Consumer가 메시지 수신
60ms  : 이메일 발송 시작 (3초 소요)
3060ms: 이메일 발송 완료
3070ms: 카카오톡 알림 시작 (2초 소요)
5070ms: 카카오톡 알림 완료
5080ms: 관리자 알림 완료

총 사용자 대기 시간: 40ms ✅
총 실제 처리 시간: 5080ms

→ RabbitMQ 없었다면 사용자는 5080ms 대기!
```

---

## 트러블슈팅

### 문제 1: LocalDateTime 직렬화 실패

**에러 메시지:**
```
InvalidDefinitionException: Java 8 date/time type `java.time.LocalDateTime`
not supported by default
```

**원인:**
Jackson의 기본 ObjectMapper는 Java 8 날짜/시간 API를 지원하지 않음

**해결 방법:**

```java
@Bean
public MessageConverter messageConverter() {
    ObjectMapper objectMapper = new ObjectMapper();

    // JavaTimeModule 등록 ✅
    objectMapper.registerModule(new JavaTimeModule());

    // 타임스탬프 대신 ISO-8601 문자열로 직렬화 ✅
    objectMapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    return new Jackson2JsonMessageConverter(objectMapper);
}
```

**의존성 추가:**
```gradle
implementation 'com.fasterxml.jackson.datatype:jackson-datatype-jsr310'
```

---

### 문제 2: RabbitMQ 연결 실패

**에러 메시지:**
```
java.net.ConnectException: Connection refused
```

**체크리스트:**

1. **RabbitMQ 컨테이너 실행 확인:**
```bash
docker ps | grep rabbitmq
```

2. **포트 확인:**
```bash
lsof -i :5672
```

3. **로그 확인:**
```bash
docker logs shoppingmall-rabbitmq
```

4. **수동 연결 테스트:**
```bash
telnet localhost 5672
```

---

### 문제 3: 메시지가 Queue에 쌓이지 않음

**체크리스트:**

1. **Exchange 존재 확인:**
   - 관리 UI → Exchanges → `order.exchange` 확인

2. **Queue 존재 확인:**
   - 관리 UI → Queues → `order.notification.queue` 확인

3. **Binding 확인:**
   - Queue 클릭 → Bindings → `order.notification` Routing Key 확인

4. **메시지 발행 로그 확인:**
```
[RabbitMQ] 주문 생성 이벤트 발행 시작: orderId=1
[RabbitMQ] 주문 생성 이벤트 발행 성공: orderId=1
```

5. **수동 메시지 발행 테스트:**
   - 관리 UI → Exchanges → order.exchange → Publish message

---

### 문제 4: Consumer가 메시지를 처리하지 않음

**체크리스트:**

1. **@RabbitListener 설정 확인:**
```java
@RabbitListener(queues = RabbitMQConfig.ORDER_NOTIFICATION_QUEUE)
```

2. **Component Scan 범위 확인:**
   - `OrderNotificationConsumer`가 `@Component`로 등록되어 있는지 확인
   - Spring Boot 애플리케이션의 `@ComponentScan` 범위에 포함되는지 확인

3. **애플리케이션 로그 확인:**
```
Registered 1 listener(s) on queue 'order.notification.queue'
```

4. **Consumer ACK 모드 확인:**
```yaml
spring:
  rabbitmq:
    listener:
      simple:
        acknowledge-mode: auto  # auto, manual, none
```

---

### 문제 5: 메시지 중복 처리

**원인:**
- Consumer 처리 중 에러 발생 → 메시지 재전송
- 네트워크 불안정 → ACK 미전달 → 재전송

**해결 방법 1: 멱등성(Idempotency) 보장**

```java
@RabbitListener(queues = RabbitMQConfig.ORDER_NOTIFICATION_QUEUE)
public void handleOrderCreated(OrderCreatedEvent event) {
    // 1. 처리 이력 확인 (DB 또는 Redis)
    if (eventProcessingRepository.exists(event.getOrderId())) {
        log.warn("이미 처리된 이벤트: orderId={}", event.getOrderId());
        return; // 중복 처리 방지
    }

    // 2. 비즈니스 로직 처리
    sendEmailNotification(event);

    // 3. 처리 이력 저장
    eventProcessingRepository.save(event.getOrderId());
}
```

**해결 방법 2: 메시지 ID 활용**

```java
@RabbitListener(queues = RabbitMQConfig.ORDER_NOTIFICATION_QUEUE)
public void handleOrderCreated(OrderCreatedEvent event,
                                @Header(AmqpHeaders.MESSAGE_ID) String messageId) {
    // messageId로 중복 처리 확인
    if (cache.contains(messageId)) {
        return;
    }

    // 처리 후 messageId 캐시에 저장 (TTL 1시간)
    cache.put(messageId, true, Duration.ofHours(1));
}
```

---

### 문제 6: 메시지 유실

**원인:**
- RabbitMQ 재시작 시 Non-Durable Queue 삭제
- Consumer가 없을 때 메시지 발행
- 네트워크 장애

**해결 방법:**

**1. Queue Durable 설정:**
```java
@Bean
public Queue orderNotificationQueue() {
    return new Queue(ORDER_NOTIFICATION_QUEUE, true); // durable = true
}
```

**2. 메시지 영속화:**
```java
rabbitTemplate.convertAndSend(
    exchange,
    routingKey,
    message,
    m -> {
        m.getMessageProperties().setDeliveryMode(MessageDeliveryMode.PERSISTENT);
        return m;
    }
);
```

**3. Publisher Confirms:**
```yaml
spring:
  rabbitmq:
    publisher-confirm-type: correlated
    publisher-returns: true
```

```java
rabbitTemplate.setConfirmCallback((correlationData, ack, cause) -> {
    if (!ack) {
        log.error("메시지 발행 실패: {}", cause);
        // DB에 실패 로그 저장 → 나중에 재발행
    }
});
```

---

## 모니터링

### RabbitMQ Management UI

**접속 정보:**
- URL: http://localhost:15672
- Username: `admin`
- Password: `admin1234`

### 주요 모니터링 지표

**1. Overview (개요)**
```
- Queued messages: 큐에 쌓인 메시지 수
- Message rate: 초당 메시지 처리량
- Connections: 활성 연결 수
- Channels: 활성 채널 수
```

**2. Queues (큐)**
```
order.notification.queue
├─ Total messages: 총 메시지 수
├─ Ready: 처리 대기 중인 메시지
├─ Unacked: 처리 중인 메시지 (ACK 대기)
├─ Publish rate: 메시지 발행 속도
└─ Deliver rate: 메시지 처리 속도
```

**3. Exchanges (교환기)**
```
order.exchange
├─ Type: direct
├─ Bindings: 바인딩된 큐 목록
└─ Message rate: 메시지 라우팅 속도
```

### 경고 임계값

| 지표 | 정상 | 주의 | 경고 |
|------|------|------|------|
| Ready messages | < 100 | 100-1000 | > 1000 |
| Unacked messages | < 10 | 10-100 | > 100 |
| Consumer utilization | > 80% | 50-80% | < 50% |
| Message rate | 안정적 | 급증/급감 | 0 (정체) |

### 알림 설정 (선택)

**Grafana + Prometheus 연동:**

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['localhost:15692']
```

**알림 규칙 예시:**
```yaml
groups:
  - name: rabbitmq_alerts
    rules:
      - alert: RabbitMQQueueTooManyMessages
        expr: rabbitmq_queue_messages_ready > 1000
        for: 5m
        annotations:
          summary: "Queue {{ $labels.queue }} has too many messages"
```

---

## 확장 가능성

### 1. Dead Letter Queue (DLQ) 추가

**목적**: 처리 실패한 메시지를 별도 큐에 저장

```java
@Bean
public Queue orderNotificationQueue() {
    return QueueBuilder.durable(ORDER_NOTIFICATION_QUEUE)
            .withArgument("x-dead-letter-exchange", "order.dlx")
            .withArgument("x-dead-letter-routing-key", "order.dead")
            .build();
}

@Bean
public Queue deadLetterQueue() {
    return new Queue("order.dead.queue", true);
}

@Bean
public DirectExchange deadLetterExchange() {
    return new DirectExchange("order.dlx");
}

@Bean
public Binding deadLetterBinding() {
    return BindingBuilder
            .bind(deadLetterQueue())
            .to(deadLetterExchange())
            .with("order.dead");
}
```

**DLQ Consumer:**
```java
@RabbitListener(queues = "order.dead.queue")
public void handleDeadLetter(OrderCreatedEvent event) {
    log.error("처리 실패한 메시지: orderId={}", event.getOrderId());

    // 1. DB에 실패 로그 저장
    // 2. 개발자에게 알림 (Slack, Email)
    // 3. 수동 재처리를 위한 관리 UI 제공
}
```

---

### 2. Message TTL (Time-To-Live) 설정

**목적**: 오래된 메시지 자동 삭제

```java
@Bean
public Queue orderNotificationQueue() {
    return QueueBuilder.durable(ORDER_NOTIFICATION_QUEUE)
            .withArgument("x-message-ttl", 3600000) // 1시간 (ms)
            .build();
}
```

---

### 3. Priority Queue (우선순위 큐)

**목적**: 중요한 메시지 우선 처리

```java
@Bean
public Queue orderNotificationQueue() {
    return QueueBuilder.durable(ORDER_NOTIFICATION_QUEUE)
            .withArgument("x-max-priority", 10) // 0-10 우선순위
            .build();
}
```

**발행 시 우선순위 설정:**
```java
rabbitTemplate.convertAndSend(
    exchange,
    routingKey,
    event,
    m -> {
        m.getMessageProperties().setPriority(5); // 우선순위 5
        return m;
    }
);
```

---

### 4. 여러 이벤트 타입 추가

**현재 구조:**
```
order.exchange → order.notification.queue (주문 생성만)
```

**확장된 구조:**
```
order.exchange
├─ order.created    → order.notification.queue
├─ order.cancelled  → order.cancel.queue
├─ order.shipped    → order.shipment.queue
└─ order.delivered  → order.delivery.queue
```

**코드 예시:**
```java
// 주문 취소 이벤트
public void publishOrderCancelled(OrderCancelledEvent event) {
    rabbitTemplate.convertAndSend(
        ORDER_EXCHANGE,
        "order.cancelled", // Routing Key
        event
    );
}

// 주문 취소 Consumer
@RabbitListener(queues = "order.cancel.queue")
public void handleOrderCancelled(OrderCancelledEvent event) {
    // 환불 처리, 재고 복구 등
}
```

---

### 5. Topic Exchange로 업그레이드

**목적**: 패턴 매칭으로 유연한 라우팅

```java
@Bean
public TopicExchange orderTopicExchange() {
    return new TopicExchange("order.topic");
}

@Bean
public Binding orderAllBinding() {
    return BindingBuilder
            .bind(orderAllQueue())
            .to(orderTopicExchange())
            .with("order.*"); // 모든 주문 이벤트
}

@Bean
public Binding orderCriticalBinding() {
    return BindingBuilder
            .bind(orderCriticalQueue())
            .to(orderTopicExchange())
            .with("order.*.critical"); // 긴급 이벤트만
}
```

**Routing Key 예시:**
```
order.created.normal    → order.* 매칭 ✅
order.created.critical  → order.* 매칭 ✅, order.*.critical 매칭 ✅
order.cancelled.normal  → order.* 매칭 ✅
```

---

## 참고 자료

### 공식 문서
- [RabbitMQ Official Documentation](https://www.rabbitmq.com/documentation.html)
- [Spring AMQP Reference](https://docs.spring.io/spring-amqp/reference/)
- [RabbitMQ Tutorials](https://www.rabbitmq.com/getstarted.html)

### 유용한 가이드
- [RabbitMQ Best Practices](https://www.cloudamqp.com/blog/part1-rabbitmq-best-practice.html)
- [Message Queue 패턴](https://microservices.io/patterns/communication-style/messaging.html)
- [AMQP Protocol Specification](https://www.amqp.org/specification/0-9-1/amqp-org-download)

### 도구
- [RabbitMQ Management Plugin](https://www.rabbitmq.com/management.html)
- [RabbitMQ Prometheus Exporter](https://github.com/rabbitmq/rabbitmq-prometheus)
- [RabbitMQ CLI Tools](https://www.rabbitmq.com/cli.html)

---

## FAQ

### Q1. RabbitMQ와 Kafka의 차이는?

| 항목 | RabbitMQ | Kafka |
|------|----------|-------|
| 타입 | Message Broker | Event Streaming Platform |
| 프로토콜 | AMQP | Custom Protocol |
| 메시지 보관 | 소비 후 삭제 | 보관 기간 설정 (재소비 가능) |
| 순서 보장 | Queue 단위 | Partition 단위 |
| 처리량 | 중간 | 매우 높음 |
| 지연 시간 | 낮음 | 중간 |
| 사용 사례 | 비즈니스 로직, 알림 | 로그 수집, 실시간 분석 |

**우리 프로젝트에서 RabbitMQ를 선택한 이유:**
- 주문 알림 등 비즈니스 로직에 적합
- 설치 및 운영이 간단
- 메시지 소비 후 즉시 삭제 (불필요한 저장 공간 사용 X)

---

### Q2. 메시지 순서가 보장되나요?

**답변:**
- **단일 Queue + 단일 Consumer**: 순서 보장 ✅
- **단일 Queue + 다중 Consumer**: 순서 보장 안 됨 ❌

**순서가 중요한 경우:**
```java
@RabbitListener(
    queues = "order.notification.queue",
    concurrency = "1" // 단일 스레드로 순차 처리
)
```

---

### Q3. RabbitMQ가 다운되면 어떻게 되나요?

**시나리오별 대응:**

1. **발행 시도 중 다운:**
   - `AmqpException` 발생
   - 로그 기록 + DB에 실패 이벤트 저장
   - 재발행 배치 작업으로 나중에 재시도

2. **메시지가 Queue에 있을 때 다운:**
   - Durable Queue + Persistent Message: 재시작 후 복구 ✅
   - Non-Durable Queue: 메시지 유실 ❌

3. **Consumer 처리 중 다운:**
   - ACK 미전송 → 메시지 재전송
   - Consumer 재시작 후 다시 처리

**클러스터링으로 고가용성 확보:**
```
RabbitMQ Node 1 ━━━━━━━━┓
                        ┣━━━ Mirror Queue
RabbitMQ Node 2 ━━━━━━━━┛
```

---

### Q4. 성능 최적화 방법은?

**1. Batch Processing:**
```java
@RabbitListener(queues = "order.queue")
public void handleBatch(List<OrderCreatedEvent> events) {
    // 100개씩 묶어서 처리
    emailService.sendBatch(events);
}
```

**2. Prefetch Count 조정:**
```yaml
spring:
  rabbitmq:
    listener:
      simple:
        prefetch: 10 # Consumer가 한 번에 가져갈 메시지 수
```

**3. Connection Pooling:**
```yaml
spring:
  rabbitmq:
    cache:
      connection:
        mode: connection
        size: 10 # 연결 풀 크기
```

---

## 다음 단계

### Phase 1: 현재 구현 완료 ✅
- [x] RabbitMQ Docker 설정
- [x] Spring AMQP 연동
- [x] 주문 생성 이벤트 발행/소비
- [x] 로깅 및 에러 처리

### Phase 2: 실제 알림 구현 (예정)
- [ ] 이메일 서비스 연동 (JavaMailSender)
- [ ] 카카오톡 알림 API 연동
- [ ] Slack 알림 (관리자용)

### Phase 3: 고급 기능 (예정)
- [ ] Dead Letter Queue 추가
- [ ] Priority Queue 설정
- [ ] Message Retry 로직
- [ ] 멱등성 처리 (중복 방지)

### Phase 4: 모니터링 & 운영 (예정)
- [ ] Prometheus + Grafana 연동
- [ ] 알림 임계값 설정
- [ ] 성능 튜닝
- [ ] 클러스터링 (고가용성)

---

**문서 버전**: 1.0.0
**최종 수정**: 2025.11.16
**작성자**: Shopping Mall Team
