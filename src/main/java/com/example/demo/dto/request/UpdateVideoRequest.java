package com.example.demo.dto.request;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * Request DTO for updating video metadata information.
 * Allows modification of video title, type, category, and associated URLs.
 * Provides validation for content type and category values.
 * 
 * @author Xander Billa
 * @since August 3, 2025
 * @see com.example.demo.service.VideoService#updateVideo(String, UpdateVideoRequest)
 * @see com.example.demo.model.Video
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UpdateVideoRequest {

    @Size(min = 1, max = 255, message = "Title must be between 1 and 255 characters")
    private String title;

    @Pattern(regexp = "^(video|trailer|poster)$", message = "Type must be one of: video, trailer, poster")
    private String type;

    @Pattern(regexp = "^(tv|movie|live)$", message = "Category must be one of: tv, movie, live")
    private String category;

    private String posterUrl;
    private String trailerUrl;
}
