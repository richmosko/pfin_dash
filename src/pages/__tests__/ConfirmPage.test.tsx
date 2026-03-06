import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import ConfirmPage from '../ConfirmPage'

// Mock the supabase client
const { mockUnsubscribe, mockOnAuthStateChange } = vi.hoisted(() => {
  const mockUnsubscribe = vi.fn()
  const mockOnAuthStateChange = vi.fn(() => ({
    data: { subscription: { unsubscribe: mockUnsubscribe } },
  }))
  return { mockUnsubscribe, mockOnAuthStateChange }
})

vi.mock('../../lib/supabase', () => ({
  supabase: {
    auth: {
      onAuthStateChange: mockOnAuthStateChange,
    },
  },
}))

function renderConfirmPage() {
  return render(
    <MemoryRouter>
      <ConfirmPage />
    </MemoryRouter>
  )
}

describe('ConfirmPage', () => {
  beforeEach(() => {
    mockOnAuthStateChange.mockClear()
    mockUnsubscribe.mockClear()
    // Reset the URL hash between tests
    window.location.hash = ''
  })

  it('renders the verifying message', () => {
    renderConfirmPage()

    expect(screen.getByRole('heading', { name: 'Verifying your email...' })).toBeInTheDocument()
    expect(screen.getByText('Please wait while we confirm your account.')).toBeInTheDocument()
  })

  it('subscribes to auth state changes on mount', () => {
    renderConfirmPage()

    expect(mockOnAuthStateChange).toHaveBeenCalledOnce()
    expect(mockOnAuthStateChange).toHaveBeenCalledWith(expect.any(Function))
  })

  it('unsubscribes on unmount', () => {
    const { unmount } = renderConfirmPage()

    unmount()

    expect(mockUnsubscribe).toHaveBeenCalledOnce()
  })

  it('shows error when URL hash contains error_description', () => {
    window.location.hash = '#error_description=Invalid+or+expired+link'

    renderConfirmPage()

    expect(screen.getByRole('heading', { name: 'Verification Failed' })).toBeInTheDocument()
    expect(screen.getByText('Invalid or expired link')).toBeInTheDocument()
  })
})
