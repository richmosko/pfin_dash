import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'

export default function ConfirmPage() {
  const navigate = useNavigate()
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event) => {
        if (event === 'SIGNED_IN') {
          navigate('/signup/success')
        }
      }
    )

    // Check for error in URL hash (Supabase puts errors there)
    const hashParams = new URLSearchParams(
      window.location.hash.substring(1)
    )
    const errorDescription = hashParams.get('error_description')
    if (errorDescription) {
      setError(errorDescription)
    }

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
