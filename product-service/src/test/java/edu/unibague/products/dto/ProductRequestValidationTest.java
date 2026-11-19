package edu.unibague.products.dto;

import jakarta.validation.Validation;
import jakarta.validation.Validator;
import org.junit.jupiter.api.Test;
import java.math.BigDecimal;
import static org.junit.jupiter.api.Assertions.*;

class ProductRequestValidationTest {
    private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

    @Test
    void acceptsValidPrice() {
        var req = new ProductRequest("Producto", "Descripcion", new BigDecimal("123.45"), 10);
        assertTrue(validator.validate(req).isEmpty());
    }

    @Test
    void rejectsTooManyDigitsAndFractionalPlaces() {
        assertFalse(validator.validate(new ProductRequest("Producto", "Descripcion", new BigDecimal("12345678901.00"), 1)).isEmpty());
        assertFalse(validator.validate(new ProductRequest("Producto", "Descripcion", new BigDecimal("12.345"), 1)).isEmpty());
    }
}
