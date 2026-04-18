#!/usr/bin/env python3
"""
ASCII Art Generator
Generates various ASCII art patterns including smiley faces, houses, and more
"""

def print_separator():
    print("=" * 50)

def smiley_face():
    """Simple smiley face"""
    art = """
         _  __
        | |/ /
        | ' / 
        | . \ 
        |_|\\_\\
        
        """
    print(art)

def smiley_detailed():
    """Detailed smiley with eyes"""
    art = """
    .-----------.
   /             \\
  |   ( ^     ^ ) |
  |      <3       |
  |    \\  O  /   |
   \\           /
    \\_________/
    """
    print(art)

def small_house():
    """A small house"""
    art = """
          __
         /  \\
        /    \\
       /______\\
      |  |  |  |
      |  |__|  |
      |________|
      |        |
      |________|
      |  |  |  |
      |__|__|__|
      """
    print(art)

def house_detailed():
    """More detailed house"""
    art = """
          /\\
         /  \\
        /    \\
       /______\\
      |  |    |  |
      |  |    |  |
      |__|____|__|
      |          |
      |          |
      |__________|
      |  |    |  |
      |__|____|__|
         |  |
         |__|
      """
    print(art)

def cat():
    """A cute cat"""
    art = """
      |\      _,,,---,,_
ZZZzz /,`.-'`'    -.  ;-;;,_
     |,4-  ) )-,_. ,\\ (  '-'
    '---''(_/--'  `-\\_)
    """
    print(art)

def rocket():
    """A rocket ship"""
    art = """
                 |\\      |
                / \\     |
               /   \\    |
              /     \\   |
             |       \\  |
             |________\\|
             /          \\
            /____________\\
           |              |
           |              |
           |______________|
    """
    print(art)

def star():
    """A star shape"""
    art = """
          *
         ***
        *****
       *******
      *********
     ***********
    *************
     ***********
      *********
       *******
        *****
         ***
          *
    """
    print(art)

def heart():
    """A heart shape"""
    art = """
         **       **
       **   **   **   **
      **      **      **
      **                   **
      **                  **
       **                **
        **              **
         **            **
          **          **
           **        **
            **      **
             **    **
              **  **
               ****
                **
    """
    print(art)

def tree():
    """A Christmas tree"""
    art = """
        *
       ***
      *****
     *******
        ||
        ||
        ||
    """
    print(art)

def sun():
    """A sun"""
    art = """
              _
           _/ \\_
         _/  O O\\_
        /    _    \\
        \\    _    /
         \\_/  \\_/
           \\   /
            \\_/
    """
    print(art)

def cloud():
    """A fluffy cloud"""
    art = """
          __      __
        /    \\__/    \\
       /                \\
       \\________________/
          ____________
    """
    print(art)

def main():
    """Display all ASCII art patterns"""
    print_separator()
    print("🎨 ASCII ART GALLERY 🎨")
    print_separator()
    
    print("\n😊 Simple Smile:")
    print("=" * 30)
    smiley_face()
    
    print("\n😁 Detailed Smile:")
    print("=" * 30)
    smiley_detailed()
    
    print("\n🏠 Simple House:")
    print("=" * 30)
    small_house()
    
    print("\n🏡 Detailed House:")
    print("=" * 30)
    house_detailed()
    
    print("\n🐱 Cat:")
    print("=" * 30)
    cat()
    
    print("\n🚀 Rocket:")
    print("=" * 30)
    rocket()
    
    print("\n⭐ Star:")
    print("=" * 30)
    star()
    
    print("\n❤️ Heart:")
    print("=" * 30)
    heart()
    
    print("\n🎄 Tree:")
    print("=" * 30)
    tree()
    
    print("\n☀️ Sun:")
    print("=" * 30)
    sun()
    
    print("\n☁️ Cloud:")
    print("=" * 30)
    cloud()
    
    print_separator()
    print("✨ Thank you for viewing! ✨")
    print_separator()

if __name__ == "__main__":
    main()
