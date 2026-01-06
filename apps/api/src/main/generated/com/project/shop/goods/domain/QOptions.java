package com.project.shop.goods.domain;

import static com.querydsl.core.types.PathMetadataFactory.*;

import com.querydsl.core.types.dsl.*;

import com.querydsl.core.types.PathMetadata;
import javax.annotation.processing.Generated;
import com.querydsl.core.types.Path;
import com.querydsl.core.types.dsl.PathInits;


/**
 * QOptions is a Querydsl query type for Options
 */
@Generated("com.querydsl.codegen.DefaultEntitySerializer")
public class QOptions extends EntityPathBase<Options> {

    private static final long serialVersionUID = 848968994L;

    private static final PathInits INITS = PathInits.DIRECT2;

    public static final QOptions options = new QOptions("options");

    public final com.project.shop.global.common.QBaseTimeEntity _super = new com.project.shop.global.common.QBaseTimeEntity(this);

    //inherited
    public final DateTimePath<java.time.LocalDateTime> cratedAt = _super.cratedAt;

    public final QGoods goods;

    public final NumberPath<Long> id = createNumber("id", Long.class);

    public final StringPath optionDescription = createString("optionDescription");

    public final ListPath<OptionCreate, SimplePath<OptionCreate>> optionValue = this.<OptionCreate, SimplePath<OptionCreate>>createList("optionValue", OptionCreate.class, SimplePath.class, PathInits.DIRECT2);

    public final NumberPath<Integer> totalPrice = createNumber("totalPrice", Integer.class);

    //inherited
    public final DateTimePath<java.time.LocalDateTime> updatedAt = _super.updatedAt;

    public QOptions(String variable) {
        this(Options.class, forVariable(variable), INITS);
    }

    public QOptions(Path<? extends Options> path) {
        this(path.getType(), path.getMetadata(), PathInits.getFor(path.getMetadata(), INITS));
    }

    public QOptions(PathMetadata metadata) {
        this(metadata, PathInits.getFor(metadata, INITS));
    }

    public QOptions(PathMetadata metadata, PathInits inits) {
        this(Options.class, metadata, inits);
    }

    public QOptions(Class<? extends Options> type, PathMetadata metadata, PathInits inits) {
        super(type, metadata, inits);
        this.goods = inits.isInitialized("goods") ? new QGoods(forProperty("goods"), inits.get("goods")) : null;
    }

}

