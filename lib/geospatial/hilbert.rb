# Copyright, 2015, by Samuel G. D. Williams. <http://www.codeotaku.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

module Geospatial
	module Hilbert
		# Quadrants are numbered 0 to 3, and are in the following order:
		# y
		# 1 | 3 | 2 |
		# 0 | 0 | 1 |
		#     0   1  x
		# The origin is in the lower left, and the most rapidly changing value is along the x axis for the initial rotation.
		
		# Four quadrants/rotations, the direction indicates the axis of the final two coordinates (e.g. 2 -> 3) and is for informal use only.
		A = 0 # LEFT
		# | 3 | 2 |
		# | 0 | 1 |
		
		B = 1 # DOWN
		# | 1 | 2 |
		# | 0 | 3 |
		
		C = 2 # RIGHT
		# | 1 | 0 |
		# | 2 | 3 |
		
		D = 3 # UP
		# | 3 | 0 |
		# | 2 | 1 |
		
		# This maps the identity rotation/quadrants into their prefix quadrant. The prefix quadrant is the 2 bit number (0 to 3) which identifies along the curve which quadrant the value falls into. This can be computed by looking at how the curve for a given rotation and looking at the correspondence between the identity quadrants and the curve's traversal.
		ROTATE = [
			[A, B, C, D], # A is the identity
			[A, D, C, B], # Map A onto B.
			[C, D, A, B], # Map A onto C.
			[C, B, A, D], # Map A onto D.
		].freeze
		
		# Rotate quadrant by rotation. The provided quadrant is with respect to the Up rotation.
		# Note that this function is self-inverting in the sense that rotate(r, rotate(r, x)) == x.
		def self.rotate(rotation, quadrant)
			ROTATE[rotation][quadrant]
		end
		
		# These prefixes are generated by the following graph:
		# Rotation | 0 1 2 3 (Prefix)
		#        A | B A A D
		#        B | A B B C
		#        C | D C C B
		#        D | C D D A
		# We can compute this matrix by looking how the given prefix quadrant maps onto a curve one level down the tree, given the current rotation. We identify that colums 1 and 2 are the same as the input so we take advantage of this by mapping only the columns which are different, i.e. for prefix 0 and 3.
		
		PREFIX0 = [B, A, D, C].freeze
		PREFIX3 = [D, C, B, A].freeze
		
		# Given the current rotation and the prefix quadrant, compute the next rotation one level down the tree.
		def self.next_rotation(rotation, prefix)
			if prefix == 0
				PREFIX0[rotation]
			elsif prefix == 3
				PREFIX3[rotation]
			else
				rotation
			end
		end
		
		# Compute which quadrant this bit is in.
		def self.normalized_quadrant(x, y, bit_offset)
			mask = 1 << bit_offset
			
			if (y & mask) == 0
				if (x & mask) == 0
					return 0
				else
					return 1
				end
			else
				if (x & mask) == 0
					return 3
				else
					return 2
				end
			end
		end
		
		# x and y must be integers, between 0..(2**order-1)
		def self.hash(x, y, order)
			value = 0
			# The initial rotation depends on the order:
			rotation = order.even? ? A : B
			
			order.downto(0) do |i|
				# This computes the normalized quadrant for the ith bit of x, y:
				quadrant = self.normalized_quadrant(x, y, i)
				
				# Given the normalised quadrant, compute the prefix bits for the given quadrant for the given hilbert curve rotation:
				prefix = rotate(rotation, quadrant)
				
				# These both do the same thing, not sure which one is faster:
				value = (value << 2) | prefix
				#result |= (rotated << (i * 2))
				
				# Given the current rotation and the prefix for the hilbert curve, compute the next rotation one level in:
				rotation = next_rotation(rotation, prefix)
			end
			
			return value
		end
		
		def self.updated_coordinate_for(quadrant, x, y)
			x = x << 1
			y = y << 1
			
			case quadrant
			when 1
				x += 1
			when 2
				x += 1
				y += 1
			when 3
				y += 1
			end
			
			return x, y
		end
		
		# Gives the order of the hilbert curve, where order 0 is defined as a single iteration of the curve.
		def self.order_of(value)
			(value.bit_length + 1) / 2 - 1
		end
		
		def self.unhash(value)
			x = 0
			y = 0
			
			rotation = A
			
			order = self.order_of(value)
			
			# The initial rotation depends on the order:
			rotation = order.even? ? A : B
			
			order.downto(0) do |i|
				# Extract the 2-bit prefix:
				prefix = (value[i*2+1] << 1) | value[i*2]
				
				# Compute the normalized quadrant:
				quadrant = self.rotate(rotation, prefix)
				
				# Compute the updated x,y coordinate for this level of the curve:
				x, y = self.updated_coordinate_for(quadrant, x, y)
				
				# Compute the next rotation of the curve one level down the tree:
				rotation = next_rotation(rotation, prefix)
			end
			
			return x, y
		end
		
		# Compute the bounds for a given normalized quadrant
		def self.bounds_for(quadrant, origin, size)
			half_size = [size[0] * 0.5, size[1] * 0.5]
			
			case quadrant
			when 0
				return origin, half_size
			when 1
				return [origin[0] + half_size[0], origin[1]], half_size
			when 2
				return [origin[0] + half_size[0], origin[1] + half_size[1]], half_size
			when 3
				return [origin[0], origin[1] + half_size[1]], half_size
			else
				raise ArgumentError.new("Invalid quadrant for computing bounds #{quadrant}")
			end
		end
		
		# Enumerate a depth first traversal of the hilbert curve from the top of the tree down.
		def self.traverse(order, origin: [0, 0], size: [1, 1], &block)
			# The initial rotation depends on the order:
			rotation = order.even? ? A : B
			value = 0
			
			if block_given?
				self.traverse_recurse(order, rotation, value, origin, size, &block)
			else
				return to_enum(:traverse_recurse, order, rotation, value, origin, size, &block)
			end
		end
		
		def self.traverse_recurse(order, rotation, value, origin, size, &block)
			# We can either traverse in prefix order or normalized quadrant order. I think prefix order is more useful since it generates a sorted output w.r.t prefix.
			4.times do |prefix|
				# Given the normalised quadrant, compute the prefix bits for the given quadrant for the given hilbert curve rotation:
				quadrant = rotate(rotation, prefix)
				
				# Compute the bounds for the given quadrant:
				child_origin, child_size = self.bounds_for(quadrant, origin, size)
				
				# These both do the same thing, not sure which one is faster:
				child_value = (value << 2) | prefix
				
				# Given the current rotation and the prefix for the hilbert curve, compute the next rotation one level in:
				child_rotation = next_rotation(rotation, prefix)
				
				#puts "quadrant=#{quadrant} child_origin=#{child_origin} child_size=#{child_size} child_value=#{child_value} order=#{order}"
				
				# We avoid calling traverse_recurse simply to hit the callback on the leaf nodes:
				result = yield child_origin, child_size, (child_value << order*2), order
				
				if order > 0 and :skip != result
					self.traverse_recurse(order - 1, child_rotation, child_value, child_origin, child_size, &block)
				end
			end
			
			return value
		end
	end
end