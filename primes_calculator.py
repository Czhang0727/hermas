#!/usr/bin/env python3
"""
Prime Number Calculator
Calculates all prime numbers from 1 to 1000 and saves them to a file.
"""

def is_prime(n):
    """Check if a number is prime."""
    if n < 2:
        return False
    if n == 2:
        return True
    if n % 2 == 0:
        return False
    for i in range(3, int(n ** 0.5) + 1, 2):
        if n % i == 0:
            return False
    return True

def main():
    primes = []
    for num in range(1, 1001):
        if is_prime(num):
            primes.append(num)
    
    # Save to file
    output_file = "primes_1_to_1000.txt"
    with open(output_file, "w") as f:
        f.write(f"Prime numbers from 1 to 1000:\n")
        f.write(f"Total count: {len(primes)}\n\n")
        f.write(", ".join(str(p) for p in primes))
    
    print(f"Found {len(primes)} prime numbers.")
    print(f"Results saved to '{output_file}'")

if __name__ == "__main__":
    main()
