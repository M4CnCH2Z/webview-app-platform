import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { HelmetProvider, Helmet } from 'react-helmet-async'; 
import { AuthProvider } from './context/AuthContext';
import { ProtectedRoute, PublicRoute } from './components/auth/ProtectedRoute';

// 레이아웃 및 페이지 컴포넌트 생략 (기존과 동일)
import Navbar from './components/layout/Navbar';
import Footer from './components/layout/Footer';
import Home from './pages/Home';
import Login from './pages/Login';
import Signup from './pages/Signup';
import GoodsList from './pages/Goods/GoodsList';
import GoodsCreate from './pages/Goods/GoodsCreate';
import GoodsDetail from './pages/Goods/GoodsDetail';
import CategoryCreate from './pages/Category/CategoryCreate';
import CartList from './pages/Cart/CartList';
import OrderCreate from './pages/Order/OrderCreate';
import OrderList from './pages/Order/OrderList';
import OrderDetail from './pages/Order/OrderDetail';
import MyPage from './pages/MyPage';
import MyPageEdit from './pages/MyPageEdit';

import 'bootstrap/dist/css/bootstrap.min.css';

function App() {
    return (
        <HelmetProvider>
            <Router>
                <AuthProvider>
                    <Helmet>
                        <title>안전한 쇼핑몰</title>
                        
                        {/* 1. MIME 스니핑 방지 */}
                        <meta http-equiv="X-Content-Type-Options" content="nosniff" />
                        
                        {/* 2. CSP 설정 최적화: 주석을 제거하고 한 줄로 연결하여 파싱 에러 방지 */}
                       <meta 
                     http-equiv="Content-Security-Policy" 
                      content="default-src 'self'; 
                                script-src 'self' 'unsafe-inline'; 
                               style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com; 
                               img-src 'self' data: blob: http://192.168.10.55:8080 http://localhost:8080 https://shoppingmall-api-bucket.s3.ap-northeast-2.amazonaws.com; 
                               connect-src 'self' http://192.168.10.55:8080 http://localhost:8080; 
                               font-src 'self' https://cdnjs.cloudflare.com;" 
                     />
                    </Helmet>

                    <div className="d-flex flex-column min-vh-100">
                        {/* 이하 레이아웃 및 라우트 설정 동일 */}
                        <Navbar />
                        <main className="flex-grow-1">
                            <Routes>
                                <Route path="/" element={<Home />} />
                                <Route path="/goods" element={<GoodsList />} />
                                <Route path="/goods/:goodsId" element={<GoodsDetail />} />
                                <Route path="/login" element={<PublicRoute><Login /></PublicRoute>} />
                                <Route path="/signup" element={<PublicRoute><Signup /></PublicRoute>} />
                                <Route path="/mypage" element={<ProtectedRoute><MyPage /></ProtectedRoute>} />
                                <Route path="/mypage/edit" element={<ProtectedRoute><MyPageEdit /></ProtectedRoute>} />
                                <Route path="/cart" element={<ProtectedRoute><CartList /></ProtectedRoute>} />
                                <Route path="/order" element={<ProtectedRoute><OrderCreate /></ProtectedRoute>} />
                                <Route path="/orders" element={<ProtectedRoute><OrderList /></ProtectedRoute>} />
                                <Route path="/orders/:orderId" element={<ProtectedRoute><OrderDetail /></ProtectedRoute>} />
                                <Route path="/goods/create" element={<ProtectedRoute><GoodsCreate /></ProtectedRoute>} />
                                <Route path="/categories/create" element={<ProtectedRoute><CategoryCreate /></ProtectedRoute>} />
                                <Route path="*" element={<div className="container mt-5">존재하지 않는 페이지입니다.</div>} />
                            </Routes>
                        </main>
                        <Footer />
                    </div>
                </AuthProvider>
            </Router>
        </HelmetProvider>
    );
}

export default App;
