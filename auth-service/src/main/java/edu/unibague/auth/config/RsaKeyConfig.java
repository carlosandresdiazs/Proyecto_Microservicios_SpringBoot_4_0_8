package edu.unibague.auth.config;

import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import com.nimbusds.jose.jwk.RSAKey;
import com.nimbusds.jose.jwk.source.ImmutableJWKSet;
import com.nimbusds.jose.jwk.JWKSet;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import edu.unibague.auth.security.PemKeyLoader;

@Configuration
public class RsaKeyConfig {
    @Bean
    RSAPublicKey rsaPublicKey(@Value("${app.jwt.public-key}") Resource resource) {
        return PemKeyLoader.readPublicKey(resource);
    }

    @Bean
    RSAPrivateKey rsaPrivateKey(@Value("${app.jwt.private-key}") Resource resource) {
        return PemKeyLoader.readPrivateKey(resource);
    }

    @Bean
    JwtEncoder jwtEncoder(RSAPublicKey publicKey, RSAPrivateKey privateKey) {
        // Un JWK de firma con kid y algoritmo concordantes con el JWS header.
        RSAKey rsa = new RSAKey.Builder(publicKey)
                .privateKey(privateKey)
                .keyID("proyecto03-key")
                .algorithm(com.nimbusds.jose.JWSAlgorithm.RS256)
                .build();
        return new NimbusJwtEncoder(new ImmutableJWKSet<>(new JWKSet(rsa)));
    }

    @Bean
    JwtDecoder jwtDecoder(RSAPublicKey publicKey) {
        return NimbusJwtDecoder.withPublicKey(publicKey)
                .signatureAlgorithm(SignatureAlgorithm.RS256)
                .build();
    }
}
