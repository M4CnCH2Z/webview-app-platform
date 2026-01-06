package com.project.shop.goods.service.Impl;

import com.project.shop.global.error.exception.BusinessException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays; // 필수: Arrays 에러 해결
import java.util.List;
import java.util.UUID;
import org.apache.tika.Tika;

// ErrorCode의 상수를 직접 참조하기 위한 static import
import static com.project.shop.global.error.ErrorCode.*;

@Service
@Transactional
public class LocalFileService {

    @Value("${file.upload.directory:uploads}")
    private String uploadDirectory;

    private static final Tika tika = new Tika();
    
    // Arrays.asList 사용
    private static final List<String> ALLOWED_MIME_TYPES = Arrays.asList("image/jpeg", "image/png", "image/gif", "application/pdf");
    private static final List<String> ALLOWED_EXTENSIONS = Arrays.asList("jpg", "jpeg", "png", "gif", "pdf");

    public List<String> upload(List<MultipartFile> multipartFiles) {
        if (multipartFiles == null || multipartFiles.isEmpty()) {
            throw new BusinessException(REQUIRED_IMAGE);
        }

        List<String> fileUrlList = new ArrayList<>();
        File uploadDir = new File(uploadDirectory);
        if (!uploadDir.exists()) {
            uploadDir.mkdirs();
        }

        for (MultipartFile file : multipartFiles) {
            if (file.isEmpty()) continue;

            String originalFileName = file.getOriginalFilename();
            // Path Traversal 방지
            if (originalFileName == null || originalFileName.contains("..")) {
                throw new BusinessException(INVALID_FILE_NAME); 
            }

            // 확장자 검증
            String extension = getFileExtension(originalFileName).toLowerCase();
            if (!ALLOWED_EXTENSIONS.contains(extension)) {
                throw new BusinessException(INVALID_FILE_EXTENSION);
            }

            try {
                // MIME 타입 검증 (Tika)
                String mimeType = tika.detect(file.getInputStream());
                if (!ALLOWED_MIME_TYPES.contains(mimeType)) {
                    throw new BusinessException(INVALID_FILE_TYPE);
                }

                // UUID 파일명 생성
                String savedFileName = UUID.randomUUID().toString() + "." + extension;
                Path filePath = Paths.get(uploadDirectory).resolve(savedFileName).normalize();

                Files.write(filePath, file.getBytes());
                fileUrlList.add("/uploads/" + savedFileName);

            } catch (IOException e) {
                throw new BusinessException(UPLOAD_ERROR_IMAGE);
            }
        }
        return fileUrlList;
    }

    private String getFileExtension(String fileName) {
        if (fileName == null) return "";
        int lastIndex = fileName.lastIndexOf(".");
        if (lastIndex == -1) return "";
        return fileName.substring(lastIndex + 1);
    }

    public void deleteFile(String fileUrl) {
        if (fileUrl == null || !fileUrl.startsWith("/uploads/")) return;
        try {
            String fileName = fileUrl.replace("/uploads/", "");
            Path filePath = Paths.get(uploadDirectory).resolve(fileName).normalize();
            Files.deleteIfExists(filePath);
        } catch (IOException e) {
            // 삭제 실패 로그 처리 가능
        }
    }
}