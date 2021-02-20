# 探索Swift中Array的底层实现

# `Array`的类型

新建一个项目，写个最简单的Demo：
```swift
var num: Array<Int> = [1, 2, 3]
```

我们点开看下`Array`的定义：

```swift
@frozen public struct Array<Element> {
    ...
}
```

很显然，从定义上来看，`Array`是一个`struct`类型，那也就是值类型了。

我们通过对[struct](https://juejin.cn/post/6919717099619221517)类型探索，知道了`struct`存的值直接在变量所在的地址的，所以我们添加一段代码查看下`num`的内存：
```swift
var num: Array<Int> = [1, 2, 3]
withUnsafePointer(to: &num) {
    print($0)
}
print("end")
```

我们可以在`print`方法处打上断点，通过调试发现：

![](https://p1-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/48b5524c050c415182466e6bf0d4e9c6~tplv-k3u1fbpfcp-watermark.image)

并没有发现有关于`Array`的值`1`，`2`，`3`的信息，内存里只有`0x000000010076f400`，看起来是一个堆上的地址，所以问题来了：
* `Array`保存的地址是什么？
* `Array`放入的数据去哪里了？
* `Array`的写时复制是如何实现的？

# 生成`Array`的`SIL`文件

我们把刚才的代码删成只有`num`的定义（越简单越清晰），然后生成[`SIL`文件](https://juejin.cn/post/6904994620628074510)查看：
```swift
sil @main : $@convention(c) (Int32, UnsafeMutablePointer<Optional<UnsafeMutablePointer<Int8>>>) -> Int32 {
bb0(%0 : $Int32, %1 : $UnsafeMutablePointer<Optional<UnsafeMutablePointer<Int8>>>):
  alloc_global @main.num : [Swift.Int]               // id: %2
  %3 = global_addr @main.num : [Swift.Int] : $*Array<Int> // user: %23
  // array有3个元素
  %4 = integer_literal $Builtin.Word, 3           // user: %6
  // array的生成方法
  // function_ref _allocateUninitializedArray<A>(_:)
  %5 = function_ref @Swift._allocateUninitializedArray<A>(Builtin.Word) -> ([A], Builtin.RawPointer) : $@convention(thin) <τ_0_0> (Builtin.Word) -> (@owned Array<τ_0_0>, Builtin.RawPointer) // user: %6
  %6 = apply %5<Int>(%4) : $@convention(thin) <τ_0_0> (Builtin.Word) -> (@owned Array<τ_0_0>, Builtin.RawPointer) // users: %8, %7
  %7 = tuple_extract %6 : $(Array<Int>, Builtin.RawPointer), 0 // user: %23
  %8 = tuple_extract %6 : $(Array<Int>, Builtin.RawPointer), 1 // user: %9
  %9 = pointer_to_address %8 : $Builtin.RawPointer to [strict] $*Int // users: %12, %19, %14
   // 字面量1
  %10 = integer_literal $Builtin.Int64, 1         // user: %11
  %11 = struct $Int (%10 : $Builtin.Int64)        // user: %12
  // 把1存入%9
  store %11 to %9 : $*Int                         // id: %12
  %13 = integer_literal $Builtin.Word, 1          // user: %14
  // %9偏移1个步长
  %14 = index_addr %9 : $*Int, %13 : $Builtin.Word // user: %17
  // 字面量2
  %15 = integer_literal $Builtin.Int64, 2         // user: %16
  %16 = struct $Int (%15 : $Builtin.Int64)        // user: %17
  // 把2存入%14
  store %16 to %14 : $*Int                        // id: %17
  %18 = integer_literal $Builtin.Word, 2          // user: %19
  // %9偏移2个步长
  %19 = index_addr %9 : $*Int, %18 : $Builtin.Word // user: %22
   // 字面量3
  %20 = integer_literal $Builtin.Int64, 3         // user: %21
  %21 = struct $Int (%20 : $Builtin.Int64)        // user: %22
  // 把3存入%19
  store %21 to %19 : $*Int                        // id: %22
  store %7 to %3 : $*Array<Int>                   // id: %23
  %24 = integer_literal $Builtin.Int32, 0         // user: %25
  %25 = struct $Int32 (%24 : $Builtin.Int32)      // user: %26
  return %25 : $Int32                             // id: %26
} // end sil function 'main'
```

从上文分析出，`num`的生成调用了`_allocateUninitializedArray<A>(_:)`的方法，该方法返回值是一个元祖`%6`，然后用`%7`、`%8`把元祖`%6`的值提取了出来，`%7`给了`%3`，也就是`num`的位置了，所以上面我们拿到的`0x000000010076f400`就是`%7`的值了，而`Array`保存的数据依次保存到了`%9`了，`%9`又是`%8`的地址指向，所以`%7`、`%8`都是什么呢？

# `Array`在源码中的定义

既然从`SIL`文件中分析不出，那么只能看源码了，我们先看下`Array`的源码：
```swift
@frozen
public struct Array<Element>: _DestructorSafeContainer {
  #if _runtime(_ObjC)
  @usableFromInline
  internal typealias _Buffer = _ArrayBuffer<Element>
  #else
  @usableFromInline
  internal typealias _Buffer = _ContiguousArrayBuffer<Element>
  #endif

  @usableFromInline
  internal var _buffer: _Buffer

  /// Initialization from an existing buffer does not have "array.init"
  /// semantics because the caller may retain an alias to buffer.
  @inlinable
  internal init(_buffer: _Buffer) {
    self._buffer = _buffer
  }
}
```

在`Array`中真的只有一个属性`_buffer`，`_buffer`在`_runtime(_ObjC)`下是`_ArrayBuffer`，否则是`_ContiguousArrayBuffer`。在苹果的设备下应该都是兼容`ObjC`，所以应该是`_ArrayBuffer`了。

我们直接断点运行下`_buffer`中被赋予了什么值。

# `_allocateUninitializedArray`

在源码中，我们搜下`SIL`文件中出现的初始化方法`_allocateUninitializedArray`，我们看到如下定义：
```swift
@inlinable // FIXME(inline-always)
@inline(__always)
@_semantics("array.uninitialized_intrinsic")
public // COMPILER_INTRINSIC
func _allocateUninitializedArray<Element>(_  builtinCount: Builtin.Word)
    -> (Array<Element>, Builtin.RawPointer) {
  let count = Int(builtinCount)
  if count > 0 {
    // Doing the actual buffer allocation outside of the array.uninitialized
    // semantics function enables stack propagation of the buffer.
    let bufferObject = Builtin.allocWithTailElems_1(
      _ContiguousArrayStorage<Element>.self, builtinCount, Element.self)

    let (array, ptr) = Array<Element>._adoptStorage(bufferObject, count: count)
    return (array, ptr._rawValue)
  }
  // For an empty array no buffer allocation is needed.
  let (array, ptr) = Array<Element>._allocateUninitialized(count)
  return (array, ptr._rawValue)
}
```

这里可以看到有个判断`count`是否大于0的，走的不同的方法，但是返回值类型是一样的，我们只想弄清楚数据结构式怎么样的，所以看其中一个就行了。我例子里的`count`是3，所以看条件语句里的。

首先看到调用了`allocWithTailElems_1`，不过调用对象是`Builtin`，不太容易看方法的实现，但我们可以走断点调试。

调试的时候发现进入了`swift_allocObject`方法：
```swift
HeapObject *swift::swift_allocObject(HeapMetadata const *metadata,
                                     size_t requiredSize,
                                     size_t requiredAlignmentMask) {
  CALL_IMPL(swift_allocObject, (metadata, requiredSize, requiredAlignmentMask));
}
```

这个[以前写过](https://juejin.cn/post/6905708198796361736)，向堆空间申请分配一块空间，断点显示的`requiredSize`值为56，`po`指针`metadata`显示的是`_TtGCs23_ContiguousArrayStorageSi_$`，我们可以知道`allocWithTailElems_1`向堆空间申请分配一块空间，申请的对象类型为`_ContiguousArrayStorage`

分配完空间后调用了`_adoptStorage`方法：

```swift
  /// Returns an Array of `count` uninitialized elements using the
  /// given `storage`, and a pointer to uninitialized memory for the
  /// first element.
  ///
  /// - Precondition: `storage is _ContiguousArrayStorage`.
  @inlinable
  @_semantics("array.uninitialized")
  internal static func _adoptStorage(
    _ storage: __owned _ContiguousArrayStorage<Element>, count: Int
  ) -> (Array, UnsafeMutablePointer<Element>) {

    let innerBuffer = _ContiguousArrayBuffer<Element>(
      count: count,
      storage: storage)

    return (
      Array(
        _buffer: _Buffer(_buffer: innerBuffer, shiftedToStartIndex: 0)),
        innerBuffer.firstElementAddress)
  }
```

我们看到`_adoptStorage`方法的返回值的内容都和`innerBuffer`有关，返回的是一个元祖，元祖里的内容分别对应了`innerBuffer`是什么？

`innerBuffer`是用`_ContiguousArrayBuffer`初始化方法生成的，看下`_ContiguousArrayBuffer`的定义：
```swift
internal struct _ContiguousArrayBuffer<Element>: _ArrayBufferProtocol {
    @inlinable
    internal init(count: Int, storage: _ContiguousArrayStorage<Element>) {
        _storage = storage
        
        _initStorageHeader(count: count, capacity: count)
    }
    
    @inlinable
    internal func _initStorageHeader(count: Int, capacity: Int) {
        #if _runtime(_ObjC)
        let verbatim = _isBridgedVerbatimToObjectiveC(Element.self)
        #else
        let verbatim = false
        #endif
        
        // We can initialize by assignment because _ArrayBody is a trivial type,
        // i.e. contains no references.
        _storage.countAndCapacity = _ArrayBody(
            count: count,
            capacity: capacity,
            elementTypeIsBridgedVerbatim: verbatim)
    }
    
    @usableFromInline
    internal var _storage: __ContiguousArrayStorageBase
}

```
`_ContiguousArrayBuffer`只有一个属性`_storage`，初始化方法`init(count: Int, storage: _ContiguousArrayStorage<Element>)`中传进来的`storage`是`_ContiguousArrayStorage`，`__ContiguousArrayStorageBase`是`_ContiguousArrayStorage`的父类。

# `_ContiguousArrayStorage`

`_ContiguousArrayStorage`是`class`，翻看了下整个`_ContiguousArrayStorage`的继承链，发现只有在`__ContiguousArrayStorageBase`中有一个属性：
```swift
final var countAndCapacity: _ArrayBody
```

那么`_ArrayBody`是什么呢
```swift
@frozen
@usableFromInline
internal struct _ArrayBody {
  @usableFromInline
  internal var _storage: _SwiftArrayBodyStorage
  
  ...
}
```

`_ArrayBody`是一个结构体，里面只有一个属性`_storage`

那`_SwiftArrayBodyStorage`又是什么呢？
```c++
struct _SwiftArrayBodyStorage {
  __swift_intptr_t count;
  __swift_uintptr_t _capacityAndFlags;
};
```

`count`和`_capacityAndFlags`都是`swift`中的指针大小，就是8个字节。

我们整理下`_ContiguousArrayStorage`这个类的内存结构，`_ContiguousArrayStorage`本身是一个类，所以有一个`metadata`，然后`_ContiguousArrayStorage`只有一个属性：
```swift
final var countAndCapacity: _ArrayBody
```
而`_ArrayBody`也只有一个属性：
```swift
@usableFromInline
  internal var _storage: _SwiftArrayBodyStorage
```
画张图可能更清晰一点
![](https://p1-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/8e464fca3a2d43b4916f7430b3013c0a~tplv-k3u1fbpfcp-watermark.image)

# `_initStorageHeader`

讲完`_ContiguousArrayStorage`的结构后，我们回到`_ContiguousArrayBuffer`初始化方法，当`_storage`赋完值后调用了：
```swift
_initStorageHeader(count: count, capacity: count)
```
看名称是在初始化`count`、`capacity`，在`_initStorageHeader`方法中看到核心内容：
```swift
_storage.countAndCapacity = _ArrayBody(
            count: count,
            capacity: capacity,
            elementTypeIsBridgedVerbatim: verbatim)
```

其实`_initStorageHeader`方法就是给`_storage`的`countAndCapacity`属性赋值而已。

接着我们看下`_ArrayBody`是如何初始化的：
```swift
@inlinable
  internal init(
    count: Int, capacity: Int, elementTypeIsBridgedVerbatim: Bool = false
  ) {
    _internalInvariant(count >= 0)
    _internalInvariant(capacity >= 0)
    
    _storage = _SwiftArrayBodyStorage(
      count: count,
      _capacityAndFlags:
        (UInt(truncatingIfNeeded: capacity) &<< 1) |
        (elementTypeIsBridgedVerbatim ? 1 : 0))
  }
```

我们看到`count`就是直接赋值了，而所谓的`capacity`（就是属性`_capacityAndFlags`）在内存中并不是直接储存，而是先向左1位位移，然后在多出来的1位数据记录了一个`elementTypeIsBridgedVerbatim`的flag。所以，如果在内存中我们读取`capacity`的时候，也要做位移操作，这个在`_ArrayBody`源码中也有体现
```swift
  /// The number of elements that can be stored in this Array without
  /// reallocation.
  @inlinable
  internal var capacity: Int {
    return Int(_capacityAndFlags &>> 1)
  }
  ```
  
  # `_ArrayBuffer`
  
  上面已经把`innerBuffer`的初始化说完了，那么回到返回值的生成：
  ```swift
  return (
      Array(
        _buffer: _Buffer(_buffer: innerBuffer, shiftedToStartIndex: 0)),
        innerBuffer.firstElementAddress)
  ```
  `Array(_buffer:)`是结构体默认的初始化方法，`_Buffer`前面也说过是`_ArrayBuffer`了，如果走断点调试也能验证。
  
  我把`_ArrayBuffer`的初始化的相关方法贴在一起，会比较好看一点：
  
  ```swift
  @usableFromInline
@frozen
internal struct _ArrayBuffer<Element>: _ArrayBufferProtocol {
...
  @usableFromInline
  internal var _storage: _ArrayBridgeStorage
}
  
extension _ArrayBuffer {
  /// Adopt the storage of `source`.
  @inlinable
  internal init(_buffer source: NativeBuffer, shiftedToStartIndex: Int) {
    _internalInvariant(shiftedToStartIndex == 0, "shiftedToStartIndex must be 0")
    _storage = _ArrayBridgeStorage(native: source._storage)
  }
  ...
}

 @usableFromInline
internal typealias _ArrayBridgeStorage
  = _BridgeStorage<__ContiguousArrayStorageBase>

@frozen
@usableFromInline
internal struct _BridgeStorage<NativeClass: AnyObject> {
    @inlinable
      @inline(__always)
      internal init(native: Native) {
        _internalInvariant(_usesNativeSwiftReferenceCounting(NativeClass.self))
        rawValue = Builtin.reinterpretCast(native)
      }
}
 
```

看到最后也没什么花样，属性都是结构体值类型的，结构体都只有一个属性，然后就是赋值操作。

`shiftedToStartIndex`传入的0对我们的理解也没有啥作用，就是做了一个判断。

综合下来，`SIL`文件中的`%7`就是_ArrayBuffer的结构体，里面有个属性存放了`_ContiguousArrayStorage`的实例类对象

# `firstElementAddress`

现在找下`SIL`文件中的`%8`，也就是`innerBuffer.firstElementAddress`：
```swift
/// A pointer to the first element.
  @inlinable
  internal var firstElementAddress: UnsafeMutablePointer<Element> {
    return UnsafeMutablePointer(Builtin.projectTailElems(_storage,
                                                         Element.self))
  }
```

很遗憾，是`Builtin`内置命令的调用，不太好看实现，不过可以看下它的解释：
```
/// projectTailElems : <C,E> (C) -> Builtin.RawPointer
///
/// Projects the first tail-allocated element of type E from a class C.
BUILTIN_SIL_OPERATION(ProjectTailElems, "projectTailElems", Special)
```

所以这个操作将返回`_storage`分配空间的尾部元素的第一个地址，这样推测下来，数组的元素储存的位置就在`_ContiguousArrayStorage`内容的后面

# 验证`Array`的底层结构

还是上面一样的代码：
```swift
var num: Array<Int> = [1, 2, 3]
withUnsafePointer(to: &num) {
    print($0)
}
print("end")
```
在`print`打上断点，输出下`num`的内存：
![](https://p1-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/3d292e3358724d95a76cf98c5b3b275d~tplv-k3u1fbpfcp-watermark.image)
`0x0000000100604b30`应该就是`_ContiguousArrayStorage`的引用了，继续输出下`0x0000000100604b30`的内存：
![](https://p6-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/d406ad758a3e41f69ac480014784a227~tplv-k3u1fbpfcp-watermark.image)

完美对上了，nice

# `Array`的写时复制

先写下写时复制的意思：只有需要改变得时候,才会对变量进行复制,如果不改变,大家都公用一个内存。在`Swift`标准库中，像是`Array`，`Dictionary`和`Set`这样的集合类型是通过写时复制`(copy-on-write)`的技术实现的

我们看下源码中是如何实现这一点的，在源码中运行如下代码：
```swift
var num: Array<Int> = [1, 2, 3]
var copyNum = num
num.append(4)
```

然后在源码的`append`方法处打上断点：
```swift
@inlinable
  @_semantics("array.append_element")
  public mutating func append(_ newElement: __owned Element) {
    // Separating uniqueness check and capacity check allows hoisting the
    // uniqueness check out of a loop.
    _makeUniqueAndReserveCapacityIfNotUnique()
    let oldCount = _getCount()
    _reserveCapacityAssumingUniqueBuffer(oldCount: oldCount)
    _appendElementAssumeUniqueAndCapacity(oldCount, newElement: newElement)
  }

```

这里一共3个方法，我们先看第一个`_makeUniqueAndReserveCapacityIfNotUnique`，看方法名理解下，就是如果该数组不是唯一的，那么使得成为唯一并且保留容量。那么这个唯一指的是什么？

我们断点调试看下，因为比较深，我copy下最关键的代码：
```c++
return !getUseSlowRC() && !getIsDeiniting() && getStrongExtraRefCount() == 0;
```

这些都是[引用计数](https://juejin.cn/post/6906438952895709197)的判断，最主要的是`getStrongExtraRefCount`强引用计数是否为0。如果不为0的话，说明不是唯一的，所以这里的唯一指的是对这块空间的唯一引用。

那如果不是唯一的话，会做什么呢？
```swift
@inlinable
  @_semantics("array.make_mutable")
  internal mutating func _makeUniqueAndReserveCapacityIfNotUnique() {
    if _slowPath(!_buffer.isMutableAndUniquelyReferenced()) {
      _createNewBuffer(bufferIsUnique: false,
                       minimumCapacity: count + 1,
                       growForAppend: true)
    }
  }
  
  @_alwaysEmitIntoClient
  @inline(never)
  internal mutating func _createNewBuffer(
    bufferIsUnique: Bool, minimumCapacity: Int, growForAppend: Bool
  ) {
    let newCapacity = _growArrayCapacity(oldCapacity: _getCapacity(),
                                         minimumCapacity: minimumCapacity,
                                         growForAppend: growForAppend)
    let count = _getCount()
    _internalInvariant(newCapacity >= count)
    
    let newBuffer = _ContiguousArrayBuffer<Element>(
      _uninitializedCount: count, minimumCapacity: newCapacity)

    if bufferIsUnique {
      _internalInvariant(_buffer.isUniquelyReferenced())

      // As an optimization, if the original buffer is unique, we can just move
      // the elements instead of copying.
      let dest = newBuffer.firstElementAddress
      dest.moveInitialize(from: _buffer.firstElementAddress,
                          count: count)
      _buffer.count = 0
    } else {
      _buffer._copyContents(
        subRange: 0..<count,
        initializing: newBuffer.firstElementAddress)
    }
    _buffer = _Buffer(_buffer: newBuffer, shiftedToStartIndex: 0)
  }
```

我们看到会调用`_createNewBuffer`方法，而`_createNewBuffer`方法里会生成一个新的`buffer`：
```swift
let newBuffer = _ContiguousArrayBuffer<Element>(
      _uninitializedCount: count, minimumCapacity: newCapacity)
```

这块内容和前面很像，就不展开了，还是比较好理解的，相当于生成了一块新的空间用于被修改后的数组。

所以，写时复制技术的本质就是查看`_ContiguousArrayStorage`的强引用计数：
* 新创建一个数组`num`，`_ContiguousArrayStorage`的强引用计数为0。
* 此刻数组`num`添加元素，发现`_ContiguousArrayStorage`的强引用计数为0，说明是自己是唯一的引用，所以直接空间末尾添加元素就行（这里就不讨论扩容的问题了）
* 当用`copyNum`复制数组`num`时，不过是把`num`的`_ContiguousArrayStorage`复制给了`copyNum`，`copyNum`的`_ContiguousArrayStorage`与`num`的`_ContiguousArrayStorage`是同一个，不过`_ContiguousArrayStorage`的强引用计数变为1了。因为这里没有开辟新的空间，非常的省性能。
* 此刻数组`num`再次添加元素，发现`_ContiguousArrayStorage`的强引用计数为1，说明是自己不是唯一的引用，开辟一块新的空间，新建一个`_ContiguousArrayStorage`，复制原有的数组内容到新空间。

我们可以自己在`Xcode`上查内存验证下
![](https://p6-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/4fe17ab41b8b45c6a8f145491e89810f~tplv-k3u1fbpfcp-watermark.image)

# 结语

`swift`的数组虽然是`struct`类型，但是数组存放的内容还是放在堆空间的。

`swift`的数组写时复制的特性是根据堆空间的引用计数判断是不是唯一引用，当数组发生改变时，检测自己不是唯一的引用，才会开始真正的复制。

最后，我把`swift`的数组的结构也用`swift`代码实现了一遍，可以从[GitHub](https://github.com/harryphone/ArrayOfSwift)下载。
