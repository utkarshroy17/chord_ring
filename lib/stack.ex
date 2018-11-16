defmodule Stack do
  def new do
    []
  end

  def push(stack, elem) do
    [elem] ++ stack
  end

  def pop(stack) do
    if length(stack) == 0 do
      raise "Stack is empty!"
    else
      {hd(stack), tl(stack)}
    end
  end
end

# a = Stack.new()
# a = Stack.push(a,1)
# a = Stack.push(a,2)
# {elem, a} = try do 
#   Stack.pop(a)
# rescue
#   RuntimeError -> {false, false }
# end
