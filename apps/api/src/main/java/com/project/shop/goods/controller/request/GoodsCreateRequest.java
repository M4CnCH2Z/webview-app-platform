package com.project.shop.goods.controller.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.springframework.lang.Nullable;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;

@Getter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class GoodsCreateRequest {

    @NotNull(message = "상품이름을 입력하세요")
    @Size(min = 2, max = 50, message = "2~50 글자수 사이로 입력해주세요.")
    private String goodsName;

    @NotNull(message = "카테고리번호를 입력하세요.")
    private Long categoryId;

    @Min(value = 1000 , message = "가격은 1000원 이상이어야 합니다.")
    private int price;

    @Nullable
    private List<OptionCreateRequest> optionCreateRequest;

    @Nullable
    private String goodsDescription;

}
