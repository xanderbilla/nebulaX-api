package com.example.demo.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Data
@Configuration
@ConfigurationProperties(prefix = "app.api")
public class ApiProperties {
    private String version = "v1";
    
    public String getBasePath() {
        return "/api/" + version;
    }
}
