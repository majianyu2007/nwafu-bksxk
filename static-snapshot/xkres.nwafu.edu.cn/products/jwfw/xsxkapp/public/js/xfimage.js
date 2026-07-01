;(function(img){
	//begin draw postion
	var start=3*Math.PI/2;
	
	//circle point(x,y) radio(r)
	var circle_x=0;
	var circle_y=0;
	var circle_r=0;
	
	var _defaultColor=['#e6f1fd','#3c66ce','#66cccc'];
	
	//auto calc param by canvas size
	function init_param(w,h){
		circle_x=w/4;
		circle_y=h/2;
		circle_r=h*2/5;
	};
	
	//translace value to use PI
	function getPercent(total,part){
	  if(total==0){
		return 0;
	  }
	  return Math.PI*2*part/total;
	};

	//calc point by add value
	function getXY(cx,cy,r,ins){
	  var x=cx+r*Math.sin(ins);
	  var y=cy-r*Math.cos(ins);
	  var newxy={'x':x,'y':y};
	  return newxy;
	};
	
	//draw part
	function drawPart(ctx,base,p1,color1,isend){
		ctx.beginPath();
		ctx.moveTo(circle_x,circle_y);
		var newxy=getXY(circle_x,circle_y,circle_r,base);
		ctx.lineTo(newxy.x,newxy.y);

		if(isend==1){
			var t1=0;
			if(p1<Math.PI/2){
				ctx.arc(circle_x,circle_y,circle_r,start+base,2*Math.PI);
			}else{
				t1=base-Math.PI/2;
			}
			ctx.arc(circle_x,circle_y,circle_r,t1,3*Math.PI/2);
		}else{
			ctx.arc(circle_x,circle_y,circle_r,start+base,start+base+p1);
		}
		ctx.lineTo(circle_x,circle_y);
		ctx.closePath();
		ctx.fillStyle=color1;
		ctx.fill();
	};
	
	//draw 
	img.draw=function(cvs,_data){
		var xf = parseFloat(_data[0].num);
		var xf1 = parseFloat(_data[1].num);
		var xf2 = parseFloat(_data[2].num);
		
		var color1 = _data[1].color || _defaultColor[1];
		var color2 = _data[2].color || _defaultColor[2];
		var color3 = _data[0].color || _defaultColor[0];
		
		init_param(cvs.width,cvs.height);
		var ctx = cvs.getContext('2d');
		
		var allxf=xf;
		if(xf1+xf2>allxf){
			allxf=xf1+xf2;
		}
		var p1=getPercent(allxf,xf1);
		var p2=getPercent(allxf,xf2);
		
		//draw 3 parts
		drawPart(ctx,0,p1,color1,0);
		drawPart(ctx,p1,p2,color2,0);
		drawPart(ctx,p1+p2,3*Math.PI/2,color3,1);
		
		//inner circle
		ctx.beginPath();
		ctx.moveTo(circle_x,circle_y);
		ctx.arc(circle_x,circle_y,circle_r/2,0,2*Math.PI);
		ctx.closePath();
		ctx.fillStyle=cvs.parentElement.bgColor || '#ffffff';
		ctx.fill();
	};

	img.drawInfo = function(infoId,_data) {
        var itemTemplate = '<div>' +
					            '<div class="cv-credit-num">@num</div>' +
					            '<div class="cv-credit-caption">@name</div>' +
					            '<div class="cv-credit-color cv-not" style="background-color: @color"></div>' +
					        '</div>';
        var html = '';
        for(var i=0,len=_data.length; i<len; i++){
            var item = _data[i];
            var num = item.num;
            var color = item.color || _defaultColor[i];
            var name = item.name;

            html += itemTemplate.replace('@num', num)
                .replace('@color', color)
                .replace('@name', name);
        }

        $(infoId).html(html);
    };
})(window.Xfimage = window.Xfimage || {});
