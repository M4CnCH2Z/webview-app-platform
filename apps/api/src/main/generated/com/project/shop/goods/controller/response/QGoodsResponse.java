package com.project.shop.goods.controller.response;

import com.querydsl.core.types.dsl.*;

import com.querydsl.core.types.ConstructorExpression;
import javax.annotation.processing.Generated;

/**
 * com.project.shop.goods.controller.response.QGoodsResponse is a Querydsl Projection type for GoodsResponse
 */
@Generated("com.querydsl.codegen.DefaultProjectionSerializer")
public class QGoodsResponse extends ConstructorExpression<GoodsResponse> {

    private static final long serialVersionUID = -1737962322L;

    public QGoodsResponse(com.querydsl.core.types.Expression<? extends com.project.shop.goods.domain.Goods> goods, com.querydsl.core.types.Expression<String> memberLoginId) {
        super(GoodsResponse.class, new Class<?>[]{com.project.shop.goods.domain.Goods.class, String.class}, goods, memberLoginId);
    }

}

