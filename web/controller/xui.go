package controller

import (
	"github.com/gin-gonic/gin"
	"x-ui/web/service"
)

type XUIController struct {
	BaseController

	inboundController *InboundController
	settingController *SettingController
}

func NewXUIController(g *gin.RouterGroup) *XUIController {
	a := &XUIController{}
	a.initRouter(g)
	return a
}

func (a *XUIController) SetUserService(userService service.UserService) {
	a.settingController.SetUserService(userService)
}

func (a *XUIController) SetInboundService(inboundService service.InboundService) {
	a.inboundController.SetInboundService(inboundService)
}

func (a *XUIController) SetSettingService(settingService service.SettingService) {
	a.settingController.SetSettingService(settingService)
}

func (a *XUIController) initRouter(g *gin.RouterGroup) {
	g = g.Group("/xui")
	g.Use(a.checkLogin)

	g.GET("/", a.index)
	g.GET("/inbounds", a.inbounds)
	g.GET("/setting", a.setting)

	a.inboundController = NewInboundController(g)
	a.settingController = NewSettingController(g)
}

func (a *XUIController) index(c *gin.Context) {
	html(c, "index.html", "系统状态", nil)
}

func (a *XUIController) inbounds(c *gin.Context) {
	html(c, "inbounds.html", "入站列表", nil)
}

func (a *XUIController) setting(c *gin.Context) {
	html(c, "setting.html", "设置", nil)
}
