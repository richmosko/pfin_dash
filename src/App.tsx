import { BrowserRouter, Routes, Route } from 'react-router-dom'
import SignupPage from './pages/SignupPage'
import ConfirmPage from './pages/ConfirmPage'
import SuccessPage from './pages/SuccessPage'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<SignupPage />} />
        <Route path="/auth/confirm" element={<ConfirmPage />} />
        <Route path="/signup/success" element={<SuccessPage />} />
      </Routes>
    </BrowserRouter>
  )
}
