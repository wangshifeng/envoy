#include "common/lua/lua.h"

#include <iostream> // fixfix

#include "common/common/assert.h"

namespace Envoy {
namespace Lua {

Coroutine::Coroutine(ThreadLocalState& parent) : parent_(parent) {
  // Reference the coroutine so it doesn't get garbage collected.
  coroutine_state_ = lua_newthread(parent.state());
  coroutine_ref_ = luaL_ref(parent.state(), LUA_REGISTRYINDEX);
  ASSERT(coroutine_ref_ != LUA_REFNIL);
}

Coroutine::~Coroutine() { luaL_unref(parent_.state(), LUA_REGISTRYINDEX, coroutine_ref_); }

void Coroutine::start(const std::string& start_function, int num_args) {
  // fixfix: perf? error checking?
  lua_getglobal(coroutine_state_, start_function.c_str());
  lua_insert(coroutine_state_, -(num_args + 1));

  int rc;
  rc = lua_resume(coroutine_state_, num_args);

  if (0 != rc) {
    std::cerr << lua_tostring(coroutine_state_, -1);
    ASSERT(false);
  }
}

ThreadLocalState::ThreadLocalState(const std::string& code) {
  state_ = lua_open();
  luaL_openlibs(state_);

  // lua_pushcfunction(state_, envoy_msleep);
  // lua_setglobal(state_, "envoy_msleep");

  if (0 != luaL_loadstring(state_, code.c_str()) || 0 != lua_pcall(state_, 0, 0, 0)) {
    ASSERT(false); // fixfix
  }
}

ThreadLocalState::~ThreadLocalState() { lua_close(state_); }

CoroutinePtr ThreadLocalState::createCoroutine() { return CoroutinePtr{new Coroutine(*this)}; }

} // namespace Lua
} // namespace Envoy
