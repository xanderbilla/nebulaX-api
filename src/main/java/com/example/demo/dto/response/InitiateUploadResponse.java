package com.example.demo.dto.response;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class InitiateUploadResponse {

    private String videoId;
    private Map<String, String> uploadUrls;
    private String s3Key;
    private String folderPath;
}
