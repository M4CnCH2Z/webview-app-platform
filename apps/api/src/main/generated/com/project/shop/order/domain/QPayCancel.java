package com.project.shop.order.domain;

import static com.querydsl.core.types.PathMetadataFactory.*;

import com.querydsl.core.types.dsl.*;

import com.querydsl.core.types.PathMetadata;
import javax.annotation.processing.Generated;
import com.querydsl.core.types.Path;
import com.querydsl.core.types.dsl.PathInits;


/**
 * QPayCancel is a Querydsl query type for PayCancel
 */
@Generated("com.querydsl.codegen.DefaultEntitySerializer")
public class QPayCancel extends EntityPathBase<PayCancel> {

    private static final long serialVersionUID = -1458515506L;

    private static final PathInits INITS = PathInits.DIRECT2;

    public static final QPayCancel payCancel = new QPayCancel("payCancel");

    public final com.project.shop.global.common.QBaseTimeEntity _super = new com.project.shop.global.common.QBaseTimeEntity(this);

    public final NumberPath<Integer> cancelPrice = createNumber("cancelPrice", Integer.class);

    public final StringPath cancelReason = createString("cancelReason");

    public final StringPath cardCompany = createString("cardCompany");

    public final StringPath cardNumber = createString("cardNumber");

    //inherited
    public final DateTimePath<java.time.LocalDateTime> cratedAt = _super.cratedAt;

    public final NumberPath<Long> id = createNumber("id", Long.class);

    public final StringPath merchantId = createString("merchantId");

    public final QOrder order;

    //inherited
    public final DateTimePath<java.time.LocalDateTime> updatedAt = _super.updatedAt;

    public QPayCancel(String variable) {
        this(PayCancel.class, forVariable(variable), INITS);
    }

    public QPayCancel(Path<? extends PayCancel> path) {
        this(path.getType(), path.getMetadata(), PathInits.getFor(path.getMetadata(), INITS));
    }

    public QPayCancel(PathMetadata metadata) {
        this(metadata, PathInits.getFor(metadata, INITS));
    }

    public QPayCancel(PathMetadata metadata, PathInits inits) {
        this(PayCancel.class, metadata, inits);
    }

    public QPayCancel(Class<? extends PayCancel> type, PathMetadata metadata, PathInits inits) {
        super(type, metadata, inits);
        this.order = inits.isInitialized("order") ? new QOrder(forProperty("order"), inits.get("order")) : null;
    }

}

