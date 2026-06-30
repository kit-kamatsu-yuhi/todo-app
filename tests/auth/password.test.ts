import { describe, it, expect } from 'vitest'
import { hashPassword, verifyPassword } from '@/lib/auth/password'

describe('hashPassword', () => {
  it('should return a hashed string different from the plain password', async () => {
    const plain = 'MySecret123!'
    const hash = await hashPassword(plain)
    expect(typeof hash).toBe('string')
    expect(hash).not.toBe(plain)
  })

  it('should return different hashes for the same password due to bcrypt salt', async () => {
    const plain = 'MySecret123!'
    const hash1 = await hashPassword(plain)
    const hash2 = await hashPassword(plain)
    expect(hash1).not.toBe(hash2)
  })
})

describe('verifyPassword', () => {
  it('should return true when the correct password is provided', async () => {
    const plain = 'MySecret123!'
    const hash = await hashPassword(plain)
    const result = await verifyPassword(plain, hash)
    expect(result).toBe(true)
  })

  it('should return false when an incorrect password is provided', async () => {
    const plain = 'MySecret123!'
    const hash = await hashPassword(plain)
    const result = await verifyPassword('WrongPassword!', hash)
    expect(result).toBe(false)
  })
})
