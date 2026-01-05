import React from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';

export const ProtectedRoute = ({ children }) => {
    const { user, loading } = useAuth();

    if (loading) return <div>보안 연결 확인 중...</div>;
    if (!user) return <Navigate to="/login" replace />; // 인증 없으면 로그인으로

    return children;
};

export const PublicRoute = ({ children }) => {
    const { user, loading } = useAuth();
    
    if (loading) return null;
    if (user) return <Navigate to="/" replace />; // 이미 로그인했으면 홈으로

    return children;
};