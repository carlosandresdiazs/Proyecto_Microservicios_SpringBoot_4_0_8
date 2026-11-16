package edu.unibague.auth.config;

import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import static org.junit.jupiter.api.Assertions.assertEquals;

class RsaKeyConfigTest {
    @Test
    void signsAndVerifiesJwtWithConfiguredRsaKeys() throws Exception {
        var generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        var keys = generator.generateKeyPair();
        var publicKey = (RSAPublicKey) keys.getPublic();
        var privateKey = (RSAPrivateKey) keys.getPrivate();
        var config = new RsaKeyConfig();
        var claims = JwtClaimsSet.builder()
                .issuer("proyecto03-auth")
                .subject("test-user")
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(60))
                .build();
        var header = JwsHeader.with(SignatureAlgorithm.RS256)
                .keyId("proyecto03-key").build();
        var token = config.jwtEncoder(publicKey, privateKey)
                .encode(JwtEncoderParameters.from(header, claims)).getTokenValue();
        var decoded = config.jwtDecoder(publicKey).decode(token);
        assertEquals("test-user", decoded.getSubject());
        assertEquals("RS256", decoded.getHeaders().get("alg"));
    }
}
