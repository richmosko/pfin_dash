import { render, screen } from '@testing-library/react'
import SignupPage from '../SignupPage'

// Mock SignupForm since it has its own test suite
vi.mock('../../components/SignupForm', () => ({
  default: () => <div data-testid="signup-form">MockedSignupForm</div>,
}))

describe('SignupPage', () => {
  it('renders the heading and subtitle', () => {
    render(<SignupPage />)

    expect(screen.getByRole('heading', { name: 'PFin Dashboard' })).toBeInTheDocument()
    expect(screen.getByText('Create your account')).toBeInTheDocument()
  })

  it('renders the signup form', () => {
    render(<SignupPage />)

    expect(screen.getByTestId('signup-form')).toBeInTheDocument()
  })
})
