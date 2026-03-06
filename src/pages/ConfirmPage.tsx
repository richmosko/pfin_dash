import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'

function getHashError(): string | null {
  const hashParams = new URLSearchParams(
    window.location.hash.substring(1)
  )
  return hashParams.get('error_description')
}

export default function ConfirmPage() {
  const navigate = useNavigate()
  const error = getHashError()

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event) => {
        if (event === 'SIGNED_IN') {
          navigate('/signup/success')
        }
      }
    )

    return () => subscription.unsubscribe()
  }, [navigate])

  if (error) {
    return (
      <div className="page">
        <h2>Verification Failed</h2>
        <p className="form-error">{error}</p>
      </div>
    )
  }

  return (
    <div className="page">
      <h2>Verifying your email...</h2>
      <p>Please wait while we confirm your account.</p>
    </div>
  )
}
