#pragma once

#include <memory>
#include <string>

#include "luajit-2.0/lua.hpp"

namespace Envoy {
namespace Lua {

// TODO: ThreadLocal wrapper

#define DECLARE_LUA_FUNCTION(Class, Name)                                                          \
  static int static_##Name(lua_State* state) {                                                     \
    return static_cast<Class*>(luaL_checkudata(state, 1, typeid(Class).name()))->Name(state);      \
  }                                                                                                \
  int Name(lua_State* state);

class ThreadLocalState;

class Coroutine {
public:
  Coroutine(ThreadLocalState& parent);
  ~Coroutine();

  void start(const std::string& start_function, int num_args);
  lua_State* state() { return coroutine_state_; }

private:
  ThreadLocalState& parent_;
  lua_State* coroutine_state_; // Does not need to be freed.
  int coroutine_ref_;
};

typedef std::unique_ptr<Coroutine> CoroutinePtr;

class ThreadLocalState {
public:
  ThreadLocalState(const std::string& code);
  ~ThreadLocalState();

  CoroutinePtr createCoroutine();
  lua_State* state() { return state_; }

private:
  lua_State* state_;
};

} // namespace Lua
} // namespace Envoy
