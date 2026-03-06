import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import SignupForm from '../SignupForm'

// Mock the supabase client
const mockSignUp = vi.fn()

vi.mock('../../lib/supabase', () => ({
  supabase: {
    auth: {
      signUp: (...args: unknown[]) => mockSignUp(...args),
    },
  },
}))

describe('SignupForm', () => {
  beforeEach(() => {
    mockSignUp.mockReset()
  })

  it('renders all form fields and submit button', () => {
    render(<SignupForm />)

    expect(screen.getByLabelText('Email')).toBeInTheDocument()
    expect(screen.getByLabelText('Password')).toBeInTheDocument()
    expect(screen.getByLabelText('Confirm Password')).toBeInTheDocument()
    expect(screen.getByLabelText('Invite Code')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Sign Up' })).toBeInTheDocument()
  })

  it('shows error when password is less than 8 characters', async () => {
    const user = userEvent.setup()
    render(<SignupForm />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.type(screen.getByLabelText('Password'), 'short')
    await user.type(screen.getByLabelText('Confirm Password'), 'short')
    await user.type(screen.getByLabelText('Invite Code'), 'ABC123')
    await user.click(screen.getByRole('button', { name: 'Sign Up' }))

    expect(screen.getByText('Password must be at least 8 characters')).toBeInTheDocument()
    expect(mockSignUp).not.toHaveBeenCalled()
  })

  it('shows error when passwords do not match', async () => {
    const user = userEvent.setup()
    render(<SignupForm />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.type(screen.getByLabelText('Password'), 'password123')
    await user.type(screen.getByLabelText('Confirm Password'), 'different123')
    await user.type(screen.getByLabelText('Invite Code'), 'ABC123')
    await user.click(screen.getByRole('button', { name: 'Sign Up' }))

    expect(screen.getByText('Passwords do not match')).toBeInTheDocument()
    expect(mockSignUp).not.toHaveBeenCalled()
  })

  it('shows error when invite code is empty', async () => {
    const user = userEvent.setup()
    render(<SignupForm />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.type(screen.getByLabelText('Password'), 'password123')
    await user.type(screen.getByLabelText('Confirm Password'), 'password123')
    // Leave invite code empty but we need to bypass the HTML required attribute
    // by directly submitting via the form's onSubmit. We'll type a space instead.
    await user.type(screen.getByLabelText('Invite Code'), '   ')
    await user.click(screen.getByRole('button', { name: 'Sign Up' }))

    expect(screen.getByText('Invite code is required')).toBeInTheDocument()
    expect(mockSignUp).not.toHaveBeenCalled()
  })

  it('calls supabase signUp with correct data on valid submission', async () => {
    mockSignUp.mockResolvedValue({ error: null })
    const user = userEvent.setup()
    render(<SignupForm />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.type(screen.getByLabelText('Password'), 'password123')
    await user.type(screen.getByLabelText('Confirm Password'), 'password123')
    await user.type(screen.getByLabelText('Invite Code'), 'ABC123')
    await user.click(screen.getByRole('button', { name: 'Sign Up' }))

    await waitFor(() => {
      expect(mockSignUp).toHaveBeenCalledWith({
        email: 'test@example.com',
        password: 'password123',
        options: {
          data: { invite_code: 'ABC123' },
          emailRedirectTo: expect.stringContaining('/auth/confirm'),
        },
      })
    })
  })

  it('shows success message after successful signup', async () => {
    mockSignUp.mockResolvedValue({ error: null })
    const user = userEvent.setup()
    render(<SignupForm />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.type(screen.getByLabelText('Password'), 'password123')
    await user.type(screen.getByLabelText('Confirm Password'), 'password123')
    await user.type(screen.getByLabelText('Invite Code'), 'ABC123')
    await user.click(screen.getByRole('button', { name: 'Sign Up' }))

    await waitFor(() => {
      expect(screen.getByText('Check your email')).toBeInTheDocument()
      expect(screen.getByText(/test@example.com/)).toBeInTheDocument()
    })
  })

  it('shows error message when signup fails', async () => {
    mockSignUp.mockResolvedValue({
      error: { message: 'User already registered' },
    })
    const user = userEvent.setup()
    render(<SignupForm />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.type(screen.getByLabelText('Password'), 'password123')
    await user.type(screen.getByLabelText('Confirm Password'), 'password123')
    await user.type(screen.getByLabelText('Invite Code'), 'ABC123')
    await user.click(screen.getByRole('button', { name: 'Sign Up' }))

    await waitFor(() => {
      expect(screen.getByText('User already registered')).toBeInTheDocument()
    })
  })

  it('disables button and shows loading text while submitting', async () => {
    // Make signUp hang so we can observe the loading state
    let resolveSignUp: (value: { error: null }) => void
    mockSignUp.mockReturnValue(
      new Promise((resolve) => {
        resolveSignUp = resolve
      })
    )
    const user = userEvent.setup()
    render(<SignupForm />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.type(screen.getByLabelText('Password'), 'password123')
    await user.type(screen.getByLabelText('Confirm Password'), 'password123')
    await user.type(screen.getByLabelText('Invite Code'), 'ABC123')
    await user.click(screen.getByRole('button', { name: 'Sign Up' }))

    // While the promise is pending, button should be disabled with loading text
    await waitFor(() => {
      const button = screen.getByRole('button', { name: 'Signing up...' })
      expect(button).toBeDisabled()
    })

    // Resolve and verify button goes back to normal
    resolveSignUp!({ error: null })

    await waitFor(() => {
      expect(screen.getByText('Check your email')).toBeInTheDocument()
    })
  })

  it('clears previous error when resubmitting', async () => {
    mockSignUp.mockResolvedValue({
      error: { message: 'Something went wrong' },
    })
    const user = userEvent.setup()
    render(<SignupForm />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.type(screen.getByLabelText('Password'), 'password123')
    await user.type(screen.getByLabelText('Confirm Password'), 'password123')
    await user.type(screen.getByLabelText('Invite Code'), 'ABC123')
    await user.click(screen.getByRole('button', { name: 'Sign Up' }))

    await waitFor(() => {
      expect(screen.getByText('Something went wrong')).toBeInTheDocument()
    })

    // Now submit again with a successful response
    mockSignUp.mockResolvedValue({ error: null })
    await user.click(screen.getByRole('button', { name: 'Sign Up' }))

    await waitFor(() => {
      expect(screen.queryByText('Something went wrong')).not.toBeInTheDocument()
    })
  })
})
