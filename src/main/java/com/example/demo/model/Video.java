package com.example.demo.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import software.amazon.awssdk.enhanced.dynamodb.mapper.annotations.DynamoDbBean;
import software.amazon.awssdk.enhanced.dynamodb.mapper.annotations.DynamoDbPartitionKey;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * Domain model representing a video entity in the Nebulax system.
 * Stores video metadata, file URLs, and categorization information in DynamoDB.
 * Supports multiple content types (video, trailer, poster) and streaming categories.
 * 
 * @author Xander Billa
 * @since August 3, 2025
 * @see com.example.demo.repository.VideoRepository
 * @see com.example.demo.service.VideoService
 * @see software.amazon.awssdk.enhanced.dynamodb.mapper.annotations.DynamoDbBean
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@DynamoDbBean
public class Video {

    @NotBlank(message = "Video ID cannot be blank")
    private String videoId;

    @NotBlank(message = "Title cannot be blank")
    @Size(min = 1, max = 255, message = "Title must be between 1 and 255 characters")
    private String title;

    @NotBlank(message = "Type cannot be blank")
    @Pattern(regexp = "^(video|trailer|poster)$", message = "Type must be one of: video, trailer, poster")
    private String type;

    @NotBlank(message = "Category cannot be blank")
    @Pattern(regexp = "^(tv|movie|live)$", message = "Category must be one of: tv, movie, live")
    private String category;

    @NotBlank(message = "Folder path cannot be blank")
    private String folderPath;

    @NotBlank(message = "Access link cannot be blank")
    private String accessLink;

    @NotNull(message = "Created date cannot be null")
    private String createdAt;

    private String modifiedAt;

    @NotBlank(message = "S3 key cannot be blank")
    private String s3Key;

    private String posterUrl;
    private String trailerUrl;

    @DynamoDbPartitionKey
    public String getVideoId() {
        return videoId;
    }
}
