package controller

import (
	"encoding/json"
	"fmt"
	"gopkg.in/yaml.v2"
	"net/http"
	"strconv"
	"time"
	"x-ui/logger"
	"x-ui/web/job"
	"x-ui/web/service"
	"x-ui/web/session"

	"github.com/gin-gonic/gin"
)

type LoginForm struct {
	Username string `json:"username" form:"username"`
	Password string `json:"password" form:"password"`
}

type IndexController struct {
	BaseController

	userService    service.UserService
	inboundService service.InboundService
}

func NewIndexController(g *gin.RouterGroup) *IndexController {
	a := &IndexController{}
	a.initRouter(g)
	return a
}

func (a *IndexController) SetUserService(userService service.UserService) {
	a.userService = userService
}

func (a *IndexController) SetInboundService(inboundService service.InboundService) {
	a.inboundService = inboundService
}

func (a *IndexController) initRouter(g *gin.RouterGroup) {
	g.GET("/", a.index)
	g.POST("/login", a.login)
	g.GET("/logout", a.logout)
	g.GET("/clash/:id", a.getClashSub)
}

func (a *IndexController) index(c *gin.Context) {
	if session.IsLogin(c) {
		c.Redirect(http.StatusTemporaryRedirect, "xui/")
		return
	}
	html(c, "login.html", "登录", nil)
}

func (a *IndexController) login(c *gin.Context) {
	var form LoginForm
	err := c.ShouldBind(&form)
	if err != nil {
		pureJsonMsg(c, false, "数据格式错误")
		return
	}
	if form.Username == "" {
		pureJsonMsg(c, false, "请输入用户名")
		return
	}
	if form.Password == "" {
		pureJsonMsg(c, false, "请输入密码")
		return
	}
	user := a.userService.CheckUser(form.Username, form.Password)
	timeStr := time.Now().Format("2006-01-02 15:04:05")
	if user == nil {
		job.NewStatsNotifyJob().UserLoginNotify(form.Username, getRemoteIp(c), timeStr, 0)
		logger.Infof("wrong username or password: \"%s\" \"%s\"", form.Username, form.Password)
		pureJsonMsg(c, false, "用户名或密码错误")
		return
	} else {
		logger.Infof("%s login success,Ip Address:%s\n", form.Username, getRemoteIp(c))
		job.NewStatsNotifyJob().UserLoginNotify(form.Username, getRemoteIp(c), timeStr, 1)
	}

	err = session.SetLoginUser(c, user)
	logger.Info("user", user.Id, "login success")
	jsonMsg(c, "登录", err)
}

func (a *IndexController) logout(c *gin.Context) {
	user := session.GetLoginUser(c)
	if user != nil {
		logger.Info("user", user.Id, "logout")
	}
	session.ClearSession(c)
	c.Redirect(http.StatusTemporaryRedirect, c.GetString("base_path"))
}

func (a *IndexController) getClashSub(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.String(400, "invalid id")
		return
	}
	inb, err := a.inboundService.GetInbound(id)
	if err != nil {
		c.String(404, "inbound not found")
		return
	}
	if string(inb.Protocol) != "vmess" {
		c.String(400, "only vmess supported")
		return
	}
	if inb.SpeedIp == "" || inb.SpeedIp == "0.0.0.0" {
		c.String(400, "speed ip not set")
		return
	}
	type wsOpts struct {
		Path    string            `yaml:"path,omitempty"`
		Headers map[string]string `yaml:"headers,omitempty"`
	}
	type h2Opts struct {
		Host []string `yaml:"host,omitempty"`
		Path string   `yaml:"path,omitempty"`
	}
	type grpcOpts struct {
		ServiceName string `yaml:"grpc-service-name,omitempty"`
	}
	type proxy struct {
		Name           string   `yaml:"name"`
		Type           string   `yaml:"type"`
		Server         string   `yaml:"server"`
		Port           int      `yaml:"port"`
		UUID           string   `yaml:"uuid"`
		AlterId        int      `yaml:"alterId"`
		Cipher         string   `yaml:"cipher"`
		TLS            bool     `yaml:"tls,omitempty"`
		Network        string   `yaml:"network,omitempty"`
		ServerName     string   `yaml:"servername,omitempty"`
		SkipCertVerify bool     `yaml:"skip-cert-verify,omitempty"`
		WsOpts         *wsOpts  `yaml:"ws-opts,omitempty"`
		H2Opts         *h2Opts  `yaml:"h2-opts,omitempty"`
		GrpcOpts       *grpcOpts `yaml:"grpc-opts,omitempty"`
	}
	type file struct {
		Proxies []proxy `yaml:"proxies"`
	}
	// parse settings
	var settings map[string]interface{}
	var stream map[string]interface{}
	_ = json.Unmarshal([]byte(inb.Settings), &settings)
	_ = json.Unmarshal([]byte(inb.StreamSettings), &stream)
	uuid := ""
	alterId := 0
	if v, ok := settings["clients"]; ok {
		if arr, ok := v.([]interface{}); ok && len(arr) > 0 {
			if cli, ok := arr[0].(map[string]interface{}); ok {
				if s, ok := cli["id"].(string); ok {
					uuid = s
				}
				if ai, ok := cli["alterId"].(float64); ok {
					alterId = int(ai)
				}
			}
		}
	}
	network := ""
	security := ""
	serverName := ""
	if v, ok := stream["network"].(string); ok {
		network = v
	}
	if v, ok := stream["security"].(string); ok {
		security = v
	}
	if security == "tls" {
		if ts, ok := stream["tlsSettings"].(map[string]interface{}); ok {
			if sni, ok := ts["serverName"].(string); ok {
				serverName = sni
			}
		}
	} else if security == "xtls" {
		if xs, ok := stream["xtlsSettings"].(map[string]interface{}); ok {
			if sni, ok := xs["serverName"].(string); ok {
				serverName = sni
			}
		}
	}
	p := proxy{
		Name:           inb.Remark,
		Type:           "vmess",
		Server:         inb.SpeedIp,
		Port:           func() int { if inb.SpeedPort > 0 { return inb.SpeedPort }; return inb.Port }(),
		UUID:           uuid,
		AlterId:        alterId,
		Cipher:         "auto",
		TLS:            security == "tls" || security == "xtls",
		Network:        network,
		ServerName:     serverName,
		SkipCertVerify: false,
	}
	if network == "ws" {
		if ws, ok := stream["wsSettings"].(map[string]interface{}); ok {
			o := &wsOpts{}
			if path, ok := ws["path"].(string); ok {
				o.Path = path
			}
			if hdrs, ok := ws["headers"].(map[string]interface{}); ok {
				o.Headers = map[string]string{}
				for k, v := range hdrs {
					if s, ok := v.(string); ok {
						o.Headers[k] = s
					}
				}
				// normalize Host key
				if host, ok := o.Headers["host"]; ok {
					o.Headers["Host"] = host
					delete(o.Headers, "host")
				}
			}
			p.WsOpts = o
		}
	} else if network == "http" {
		if h2, ok := stream["httpSettings"].(map[string]interface{}); ok {
			o := &h2Opts{}
			if path, ok := h2["path"].(string); ok {
				o.Path = path
			}
			if hosts, ok := h2["host"].([]interface{}); ok {
				for _, hv := range hosts {
					if s, ok := hv.(string); ok && s != "" {
						o.Host = append(o.Host, s)
					}
				}
			}
			p.H2Opts = o
		}
	} else if network == "grpc" {
		if g, ok := stream["grpcSettings"].(map[string]interface{}); ok {
			o := &grpcOpts{}
			if sn, ok := g["serviceName"].(string); ok {
				o.ServiceName = sn
			}
			p.GrpcOpts = o
		}
	}
	out := file{Proxies: []proxy{p}}
	bs, err := yaml.Marshal(out)
	if err != nil {
		c.String(500, "build yaml failed")
		return
	}
	filename := fmt.Sprintf("clash_%d.yaml", inb.Id)
	if inb.Remark != "" {
		filename = fmt.Sprintf("clash_%s.yaml", inb.Remark)
	}
	c.Header("Content-Type", "application/x-yaml")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", filename))
	_, _ = c.Writer.Write(bs)
}
