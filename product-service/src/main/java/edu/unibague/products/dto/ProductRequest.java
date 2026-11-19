package edu.unibague.products.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

public record ProductRequest(
 @NotBlank @Size(max=120) String name,
 @NotBlank @Size(max=500) String description,
 @NotNull @DecimalMin("0.00") @Digits(integer=10, fraction=2) BigDecimal price,
 @NotNull @Min(0) Integer stock
) {}
