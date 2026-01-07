package controller

import (
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"gopkg.in/yaml.v2"
	"strconv"
	"x-ui/database/model"
	"x-ui/logger"
	"x-ui/web/global"
	"x-ui/web/service"
	"x-ui/web/session"
)

type InboundController struct {
	inboundService service.InboundService
	xrayService    service.XrayService
}

func NewInboundController(g *gin.RouterGroup) *InboundController {
	a := &InboundController{}
	a.initRouter(g)
	a.startTask()
	return a
}

func (a *InboundController) initRouter(g *gin.RouterGroup) {
	g = g.Group("/inbound")

	g.POST("/list", a.getInbounds)
	g.POST("/add", a.addInbound)
	g.POST("/del/:id", a.delInbound)
	g.POST("/update/:id", a.updateInbound)
	g.GET("/clash/:id", a.getClashSub)
}

func (a *InboundController) startTask() {
	webServer := global.GetWebServer()
	c := webServer.GetCron()
	c.AddFunc("@every 10s", func() {
		if a.xrayService.IsNeedRestartAndSetFalse() {
			err := a.xrayService.RestartXray(false)
			if err != nil {
				logger.Error("restart xray failed:", err)
			}
		}
	})
}

func (a *InboundController) getInbounds(c *gin.Context) {
	user := session.GetLoginUser(c)
	inbounds, err := a.inboundService.GetInbounds(user.Id)
	if err != nil {
		jsonMsg(c, "获取", err)
		return
	}
	jsonObj(c, inbounds, nil)
}

func (a *InboundController) addInbound(c *gin.Context) {
	inbound := &model.Inbound{}
	err := c.ShouldBind(inbound)
	if err != nil {
		jsonMsg(c, "添加", err)
		return
	}
	user := session.GetLoginUser(c)
	inbound.UserId = user.Id
	inbound.Enable = true
	inbound.Tag = fmt.Sprintf("inbound-%v", inbound.Port)
	err = a.inboundService.AddInbound(inbound)
	jsonMsg(c, "添加", err)
	if err == nil {
		a.xrayService.SetToNeedRestart()
	}
}

func (a *InboundController) delInbound(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		jsonMsg(c, "删除", err)
		return
	}
	err = a.inboundService.DelInbound(id)
	jsonMsg(c, "删除", err)
	if err == nil {
		a.xrayService.SetToNeedRestart()
	}
}

func (a *InboundController) updateInbound(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		jsonMsg(c, "修改", err)
		return
	}
	inbound := &model.Inbound{
		Id: id,
	}
	err = c.ShouldBind(inbound)
	if err != nil {
		jsonMsg(c, "修改", err)
		return
	}
	err = a.inboundService.UpdateInbound(inbound)
	jsonMsg(c, "修改", err)
	if err == nil {
		a.xrayService.SetToNeedRestart()
	}
}

func (a *InboundController) getClashSub(c *gin.Context) {
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
