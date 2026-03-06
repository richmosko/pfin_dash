import { render, screen } from '@testing-library/react'
import SuccessPage from '../SuccessPage'

describe('SuccessPage', () => {
  it('renders the welcome heading', () => {
    render(<SuccessPage />)

    expect(screen.getByRole('heading', { name: 'Welcome!' })).toBeInTheDocument()
  })

  it('renders the verification and coming soon messages', () => {
    render(<SuccessPage />)

    expect(screen.getByText('Your email has been verified and your account is active.')).toBeInTheDocument()
    expect(screen.getByText('The dashboard is coming soon.')).toBeInTheDocument()
  })
})
